{-# LANGUAGE OverloadedStrings #-}

module WASM
  ( Expression(..)
  , Module(..)
  , printWasm
  , forestExprToWasm
  , forestModuleToWasm
  ) where

import qualified Lib as F

import Control.Arrow ((***))
import Data.List (intercalate)
import Data.Maybe
import Data.Semigroup ((<>))
import Data.Text (Text)

newtype Module =
  Module [Expression]

data Expression
  = Const Int
  | Func String
         [String]
         Expression
  | GetLocal String
  | Call String
         [Expression]
  | NamedCall String
              [Expression]
  | If Expression
       Expression
       (Maybe Expression)

indent :: Int -> String -> String
indent level str =
  intercalate "\n" $ map (\line -> replicate level ' ' ++ line) (lines str)

indent2 :: String -> String
indent2 = indent 2

forestModuleToWasm :: F.Module -> Module
forestModuleToWasm (F.Module fexprs) = Module (forestExprToWasm <$> fexprs)

forestExprToWasm :: F.Expression -> Expression
forestExprToWasm fexpr =
  case fexpr of
    F.Identifier i -> GetLocal i
    F.Number n -> Const n
    F.Assignment name args fexpr -> Func name args (forestExprToWasm fexpr)
    F.BetweenParens fexpr -> forestExprToWasm fexpr
    F.Infix operator a b ->
      Call (funcForOperator operator) [forestExprToWasm a, forestExprToWasm b]
    F.Call name arguments -> NamedCall name (map forestExprToWasm arguments)
    F.Case caseFexpr patterns ->
      constructCase (forestExprToWasm caseFexpr) (patternsToWasm patterns)
  where
    constructCase :: Expression -> [(Expression, Expression)] -> Expression
    constructCase caseExpr patterns =
      case patterns of
        [x] ->
          If (Call "i32.eq" [caseExpr, fst x]) (snd (head patterns)) Nothing
        (x:xs) ->
          If
            (Call "i32.eq" [caseExpr, fst x])
            (snd x)
            (Just (constructCase caseExpr xs))
        [] -> undefined -- TODO use nonempty to force this
    patternsToWasm = map (forestExprToWasm *** forestExprToWasm)

funcForOperator :: F.OperatorExpr -> String
funcForOperator operator =
  case operator of
    F.Add -> "i32.add"
    F.Subtract -> "i32.sub"
    F.Multiply -> "i32.mul"
    F.Divide -> "i32.div_s"

printWasm :: Module -> String
printWasm (Module expressions) =
  "(module\n" ++
  indent2 (intercalate "\n" $ map printWasmExpr expressions) ++ "\n)"
  where
    printWasmExpr expr =
      case expr of
        Const n -> "(i32.const " ++ show n ++ ")"
        GetLocal name -> "(get_local $" ++ name ++ ")"
        Call name args ->
          "(" ++
          name ++ "\n" ++ indent2 (unlines (printWasmExpr <$> args)) ++ "\n)"
        NamedCall name args ->
          "(call $" ++
          name ++ "\n" ++ indent2 (unlines (printWasmExpr <$> args)) ++ "\n)"
        If conditional a b ->
          unlines
            ([ "(if (result i32)"
             , indent2 $ printWasmExpr conditional
             , indent2 $ printWasmExpr a
             ] <>
             [indent2 $ maybe "(i32.const 0)" printWasmExpr b, ")"])
        Func name args body ->
          unlines
            [ "(export \"" ++ name ++ "\" (func $" ++ name ++ "))"
            , "(func $" ++
              name ++
              unwords (map (\x -> " (param $" ++ x ++ " i32)") args) ++
              " (result i32)"
            , indent2 $ unlines ["(return", indent2 $ printWasmExpr body, ")"]
            , ")"
            ]
