{- | Module: Main
 Copyright: (C) Liqwid Labs 2022
 License: Apache 2.0
 Portability: GHC only
 Stability: Experimental

 Example of @plutarch-quickcheck@ tests. These are meant to be read as source
 code.
-}
module Main (main) where

import Data.Tagged (Tagged (Tagged))
import Data.Universe (
    Finite (cardinality, universeF),
    Universe (universe),
 )

import Plutarch (PCon (pcon), S, Term, plam, (#), type (:-->))
import Plutarch.Integer (PInteger, PIntegral (pquot))
import Plutarch.Maybe (PMaybe (..))
import Plutarch.Trace (ptraceError)

import Test.QuickCheck (
    Arbitrary (arbitrary, shrink),
    Gen,
    Property,
 )
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.ExpectedFailure (expectFailBecause)
import Test.Tasty.Plutarch.Property (classifiedProperty)
import Test.Tasty.QuickCheck (testProperty)

data HandlerCases = EvenNumber | OddNumber
    deriving stock (Eq, Show)

instance Universe HandlerCases where
    universe = [EvenNumber, OddNumber]

instance Finite HandlerCases where
    universeF = universe
    cardinality = Tagged 2

classifier :: Integer -> HandlerCases
classifier a
    | even a = EvenNumber
    | otherwise = OddNumber

generator :: HandlerCases -> Gen Integer
generator EvenNumber = (arbitrary :: Gen Integer) >>= (\number -> return $ number * 2)
generator OddNumber = (arbitrary :: Gen Integer) >>= (\number -> return $ number * 2 + 1)

shrinker :: Integer -> [Integer]
shrinker = shrink

expectedFailureSucceeding :: Property
expectedFailureSucceeding = classifiedProperty generator shrinker expected classifier definition
  where
    expected :: forall (s :: S). Term s (PInteger :--> PMaybe PInteger)
    expected = plam $ const $ pcon PNothing

    definition :: forall (s :: S). Term s (PInteger :--> PInteger)
    definition = pquot # 2

expectedFailureFailing :: Property
expectedFailureFailing = classifiedProperty generator shrinker expected classifier definition
  where
    expected :: forall (s :: S). Term s (PInteger :--> PMaybe PInteger)
    expected = plam $ const $ pcon PNothing

    definition :: forall (s :: S). Term s (PInteger :--> PInteger)
    definition = plam $ const $ ptraceError "failure"

expectedSuccessFailing :: Property
expectedSuccessFailing = classifiedProperty generator shrinker expected classifier definition
  where
    expected :: forall (s :: S). Term s (PInteger :--> PMaybe PInteger)
    expected = plam $ \x -> pcon $ PJust x

    definition :: forall (s :: S). Term s (PInteger :--> PInteger)
    definition = plam $ const $ ptraceError "failure"

expectedSuccessIncorrectValue :: Property
expectedSuccessIncorrectValue = classifiedProperty generator shrinker expected classifier definition
  where
    expected :: forall (s :: S). Term s (PInteger :--> PMaybe PInteger)
    expected = plam $ \x -> pcon $ PJust x

    definition :: forall (s :: S). Term s (PInteger :--> PInteger)
    definition = plam (+ 1)

expectedSuccessCorrectValue :: Property
expectedSuccessCorrectValue = classifiedProperty generator shrinker expected classifier definition
  where
    expected :: forall (s :: S). Term s (PInteger :--> PMaybe PInteger)
    expected = plam $ \x -> pcon $ PJust x

    definition :: forall (s :: S). Term s (PInteger :--> PInteger)
    definition = plam id

main :: IO ()
main = do
    defaultMain . testGroup "Possible outputs of classifiedProperty" $
        [ expectFailBecause "expects failure but script runs successfully" $
            testProperty "\"expected: Failure/yields: Success\"" expectedFailureSucceeding
        , testProperty "\"expected: Failure/yields: Failure\"" expectedFailureFailing
        , expectFailBecause "expects success but script crashed" $
            testProperty "\"expected: Success/yields: Failure\"" expectedSuccessFailing
        , expectFailBecause "Yielded value is incorrect" $
            testProperty "\"expected: Success/yields: Success but Incorrect\"" expectedSuccessIncorrectValue
        , testProperty "\"expected: Success/yields: Success and Correct\"" expectedSuccessCorrectValue
        ]
