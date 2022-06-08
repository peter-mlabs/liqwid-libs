{-# LANGUAGE TypeApplications #-}

module Plutarch.Extra.List (
    pnotNull,
    pmergeBy,
    phalve,
    pmsortBy,
    pmsort,
    pnubSortBy,
    pnubSort,
    pisUniqBy,
    pisUniq,
    pmapMaybe,
    pfind',
    pfirstJust,
    plookup,
    pbinarySearchBy,
    pbinarySearch,
    plookupTuple,
    module Extra,
) where

import Data.Kind (Type)
import Plutarch (
    PCon (pcon),
    PMatch (pmatch),
    S,
    Term,
    pfix,
    phoistAcyclic,
    plam,
    plet,
    unTermCont,
    (#),
    (#$),
    type (:-->),
 )
import Plutarch.Api.V1.Tuple (PTuple)
import Plutarch.Bool (PBool (..), PEq (..), POrd (..), pif)
import Plutarch.Builtin (PAsData, PBuiltinPair, PIsData, pfromData, pfstBuiltin, psndBuiltin)
import Plutarch.DataRepr (pfield)
import "plutarch-extra" Plutarch.Extra.List as Extra (
    pcheckSorted,
    preverse,
 )
import Plutarch.Extra.TermCont (pletC)
import Plutarch.List (PIsListLike, PListLike (..), plength, precList, psingleton)
import Plutarch.Maybe (PMaybe (PJust, PNothing))
import Plutarch.Pair (PPair (..))
import Prelude hiding (last)

{- | True if a list is not empty.

   @since 1.0.0
-}
pnotNull ::
    forall (a :: S -> Type) (s :: S) list.
    PIsListLike list a =>
    Term
        s
        (list a :--> PBool)
pnotNull =
    phoistAcyclic $
        plam $
            pelimList (\_ _ -> pcon PTrue) (pcon PFalse)

{- | / O(n) /. Merge two lists which are assumed to be ordered, given a custom comparator.
    The comparator should return true if first value is less than the second one.

   @since 1.0.0
-}
pmergeBy ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term
        s
        ( (a :--> a :--> PBool)
            :--> list a
            :--> list a
            :--> list a
        )
pmergeBy = phoistAcyclic $ pfix #$ plam go
  where
    go self comp a b =
        pif (pnull # a) b $
            pif (pnull # b) a $
                unTermCont $ do
                    ah <- pletC $ phead # a
                    at <- pletC $ ptail # a
                    bh <- pletC $ phead # b
                    bt <- pletC $ ptail # b

                    pure $
                        pif
                            (comp # ah # bh)
                            (pcons # ah #$ self # comp # at # b)
                            (pcons # bh #$ self # comp # a # bt)

{- | Split a list in half without any dividing.

   @since 1.0.0
-}
phalve ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term s (list a :--> PPair (list a) (list a))
phalve = phoistAcyclic $ plam $ \l -> go # l # l
  where
    go = phoistAcyclic $ pfix # plam go'
    go' self xs ys =
        pif
            (pnull # ys)
            (pcon $ PPair pnil xs)
            ( unTermCont $ do
                yt <- pletC $ ptail # ys

                xh <- pletC $ phead # xs
                xt <- pletC $ ptail # xs

                pure $
                    pif (pnull # yt) (pcon $ PPair (psingleton # xh) xt) $
                        unTermCont $ do
                            yt' <- pletC $ ptail # yt
                            pure $
                                pmatch (self # xt # yt') $ \(PPair first last) ->
                                    pcon $ PPair (pcons # xh # first) last
            )

{- | / O(nlogn) /. Merge sort, bottom-up version, given a custom comparator.

   Assuming the comparator returns true if first value is less than the second one,
    the list elements will be arranged in ascending order, keeping duplicates in the order
    they appeared in the input.

   @since 1.0.0
-}
pmsortBy ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term
        s
        ( (a :--> a :--> PBool)
            :--> list a
            :--> list a
        )
pmsortBy = phoistAcyclic $ pfix #$ plam go
  where
    go self comp xs = pif (pnull # xs) pnil $
        pif (pnull #$ ptail # xs) xs $
            pmatch (phalve # xs) $ \(PPair fh sh) ->
                let sfh = self # comp # fh
                    ssh = self # comp # sh
                 in pmergeBy # comp # sfh # ssh

{- | A special case of 'pmsortBy' which requires elements have 'POrd' instance.

   @since 1.0.0
-}
pmsort ::
    forall (a :: S -> Type) (s :: S) list.
    (POrd a, PIsListLike list a) =>
    Term s (list a :--> list a)
pmsort = phoistAcyclic $ pmsortBy # comp
  where
    comp = phoistAcyclic $ plam (#<)

{- | / O(nlogn) /. Sort and remove dupicate elements in a list.

    The first parameter is a equalator, which should return true if the two given values are equal.
    The second parameter is a comparator, which should returns true if the first value is less than the second value.

    @since 1.0.0
-}
pnubSortBy ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term
        s
        ( (a :--> a :--> PBool)
            :--> (a :--> a :--> PBool)
            :--> list a
            :--> list a
        )
pnubSortBy = phoistAcyclic $
    plam $ \eq comp l -> pif (pnull # l) l $
        unTermCont $ do
            sl <- pletC $ pmsortBy # comp # l

            let x = phead # sl
                xs = ptail # sl

            return $ go # eq # x # xs
  where
    go = phoistAcyclic pfix #$ plam go'
    go' self eq seen l =
        pif (pnull # l) (psingleton # seen) $
            unTermCont $ do
                x <- pletC $ phead # l
                xs <- pletC $ ptail # l

                return $
                    pif
                        (eq # x # seen)
                        (self # eq # seen # xs)
                        (pcons # seen #$ self # eq # x # xs)

{- | Special version of 'pnubSortBy', which requires elements have 'POrd' instance.

   @since 1.0.0
-}
pnubSort ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a, POrd a) =>
    Term s (list a :--> list a)
pnubSort = phoistAcyclic $ pnubSortBy # eq # comp
  where
    eq = phoistAcyclic $ plam (#==)
    comp = phoistAcyclic $ plam (#<)

{- | / O(nlogn) /. Check if a list contains no duplicates.

   @since 1.0.0
-}
pisUniqBy ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term
        s
        ( (a :--> a :--> PBool)
            :--> (a :--> a :--> PBool)
            :--> list a
            :--> PBool
        )
pisUniqBy = phoistAcyclic $
    plam $ \eq comp xs ->
        let nubbed = pnubSortBy # eq # comp # xs
         in plength # xs #== plength # nubbed

{- | A special case of 'pisUniqBy' which requires elements have 'POrd' instance.

   @since 1.0.0
-}
pisUniq ::
    forall (a :: S -> Type) (s :: S) list.
    (POrd a, PIsListLike list a) =>
    Term s (list a :--> PBool)
pisUniq = phoistAcyclic $ pisUniqBy # eq # comp
  where
    eq = phoistAcyclic $ plam (#==)
    comp = phoistAcyclic $ plam (#<)

{- | A special version of `pmap` which allows list elements to be thrown out.

    @since 1.0.0
-}
pmapMaybe ::
    forall (a :: S -> Type) (s :: S) list.
    (PIsListLike list a) =>
    Term
        s
        ( (a :--> PMaybe a)
            :--> list a
            :--> list a
        )
pmapMaybe = phoistAcyclic $
    pfix #$ plam $ \self f l -> pif (pnull # l) pnil $
        unTermCont $ do
            x <- pletC $ phead # l
            xs <- pletC $ ptail # l

            pure $
                pmatch (f # x) $ \case
                    PJust ux -> pcons # ux #$ self # f # xs
                    _ -> self # f # xs

{- | Get the first element that matches a predicate or return Nothing.

     @since 1.0.0
-}
pfind' ::
    forall (a :: S -> Type) (s :: S) list.
    PIsListLike list a =>
    (Term s a -> Term s PBool) ->
    Term s (list a :--> PMaybe a)
pfind' p =
    precList
        (\self x xs -> pif (p x) (pcon (PJust x)) (self # xs))
        (const $ pcon PNothing)

{- | Get the first element that maps to a 'PJust' in a list.

     @since 1.0.0
-}
pfirstJust ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S) list.
    PIsListLike list a =>
    Term s ((a :--> PMaybe b) :--> list a :--> PMaybe b)
pfirstJust =
    phoistAcyclic $
        plam $ \p ->
            precList
                ( \self x xs ->
                    -- In the future, this should use `pmatchSum`, I believe?
                    pmatch (p # x) $ \case
                        PNothing -> self # xs
                        PJust v -> pcon (PJust v)
                )
                (const $ pcon PNothing)

{- | /O(n)/. Find the value for a given key in an associative list.

     @since 1.0.0
-}
plookup ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S) list.
    (PEq a, PIsListLike list (PBuiltinPair a b)) =>
    Term s (a :--> list (PBuiltinPair a b) :--> PMaybe b)
plookup =
    phoistAcyclic $
        plam $ \k xs ->
            pmatch (pfind' (\p -> pfstBuiltin # p #== k) # xs) $ \case
                PNothing -> pcon PNothing
                PJust p -> pcon (PJust (psndBuiltin # p))

{- | /O(n)/. Find the value for a given key in an assoclist which uses 'PTuple's.

     @since 1.0.0
-}
plookupTuple ::
    (PEq a, PIsListLike list (PAsData (PTuple a b)), PIsData a, PIsData b) =>
    Term s (a :--> list (PAsData (PTuple a b)) :--> PMaybe b)
plookupTuple =
    phoistAcyclic $
        plam $ \k xs ->
            pmatch (pfind' (\p -> (pfield @"_0" # pfromData p) #== k) # xs) $ \case
                PNothing -> pcon PNothing
                PJust p -> pcon (PJust (pfield @"_1" # pfromData p))

{- | /O(logn)/. Search for a target in a list using binary search. The list should be sorted in in ascending order.

    The first parameter is a equalator, which should return true if the two given values are equal.
    The second parameter is a comparator, which should returns true if the first value is less than the second value.
    The third parameter is the target which is being search for.

     @since 1.0.0
-}
pbinarySearchBy ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S) l.
    (PIsListLike l a) =>
    Term
        s
        ( (a :--> b :--> PBool)
            :--> (a :--> b :--> PBool)
            :--> b
            :--> l a
            :--> PMaybe a
        )
pbinarySearchBy = phoistAcyclic $ pfix # go
  where
    go = phoistAcyclic $
        plam $ \self eq comp target inp ->
            pif
                (pnull # inp)
                (pcon PNothing)
                $ pmatch
                    (phalve # inp)
                    $ \(PPair fh sh) ->
                        pif
                            (pnull # sh)
                            ( let x = phead # fh
                               in pif
                                    (eq # x # target)
                                    (pcon $ PJust x)
                                    (pcon PNothing)
                            )
                            $ plet (phead # sh) $ \mid ->
                                pif
                                    (eq # mid # target)
                                    (pcon $ PJust mid)
                                    $ pif
                                        (comp # mid # target)
                                        ( let next =
                                                ptail # sh
                                           in self # eq # comp # target # next
                                        )
                                        $ self # eq # comp # target # fh

{- | A special version of 'pbinarySearchBy', given a term to convert list element type @a@ to another type @b@,
     and type @b@ has 'POrd' instance.

     @since 1.0.0
-}
pbinarySearch ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S) l.
    (POrd b, PIsListLike l a) =>
    Term
        s
        ( (a :--> b)
            :--> b
            :--> l a
            :--> PMaybe a
        )
pbinarySearch = phoistAcyclic $
    plam $ \conv target list ->
        let eq = plam $ \x y -> (conv # x) #== y
            comp = plam $ \x y -> (conv # x) #< y
         in pbinarySearchBy # eq # comp # target # list
