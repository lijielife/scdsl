module LogicSolve(solveLogic) where

import GLPKSolve (solveLEInt)
import Data.List (foldl', genericLength) 
import LogicDefs

-- Symbolic reasoning

isPVar :: EquationTerm a -> Bool
isPVar (Var _) = True
isPVar _ = False

isNVar :: EquationTerm a -> Bool
isNVar (NegVar _) = True
isNVar _ = False

isConst :: EquationTerm a -> Bool
isConst (Const _) = True
isConst _ = False

getConst :: EquationTerm a -> Integer 
getConst (Const x) = x
getConst _ = error "getConst: not a const!"

isAnd :: Logic a -> Bool
isAnd (And _) = True
isAnd _ = False

isOr :: Logic a -> Bool
isOr (Or _) = True
isOr _ = False

negateEq :: Equation a -> Equation a
negateEq (LE a b) = (LE (Const 1:b) a)

negateLogic :: Logic a -> Logic a
negateLogic (Eq x) = Eq (negateEq x)
negateLogic (Not l) = l
negateLogic (And l) = Or $ map negateLogic l
negateLogic (Or l) = And $ map negateLogic l

removeNots :: Logic a -> Logic a
removeNots (Eq x) = Eq x
removeNots (Not l) = removeNots (negateLogic l)
removeNots (And l) = And $ map removeNots l
removeNots (Or l) = Or $ map removeNots l

findAndSeparateAux :: (a -> Bool) -> [a] -> [a] -> Maybe (a, [a])
findAndSeparateAux _ [] _ = Nothing
findAndSeparateAux f (h:t) acc
 | f h = Just (h, acc ++ t)
 | otherwise = findAndSeparateAux f t (h:acc)

findAndSeparate :: (a -> Bool) -> [a] -> Maybe (a, [a])
findAndSeparate f l = findAndSeparateAux f l []

findAndSeparateAnds :: [Logic a] -> Maybe (Logic a, [Logic a])
findAndSeparateAnds = findAndSeparate isAnd

findAndSeparateOrs :: [Logic a] -> Maybe (Logic a, [Logic a])
findAndSeparateOrs = findAndSeparate isOr

-- pushAnds: assumes there are no Not's
pushAnds :: Logic a -> Logic a
pushAnds (Eq x) = Eq x
pushAnds (Not _) = error "Not found in pushAnds!"
pushAnds (And l) =
  case findAndSeparateAnds l of
    Just (And h, t) -> pushAnds (And (h ++ t))
    Just (_, _) -> error "findAndSeparateAnds found something other than an And!"
    Nothing ->
       case findAndSeparateOrs l of
         Just (Or h, t) -> pushAnds $ Or [And (x:t) | x <- h]
         Just (_, _) -> error "findAndSeparateOrs found something other than an Or!"
         Nothing -> And (map pushAnds l)
pushAnds (Or l) = Or (map pushAnds l)

flattenOrs :: Logic a -> Logic a
flattenOrs (Eq x) = Eq x
flattenOrs (Not _) = error "Not found in flattenOrs!"
flattenOrs (And l) = And (map flattenOrs l)
flattenOrs (Or l) =
  case findAndSeparateOrs l of
    Just (Or h, t) -> flattenOrs $ Or (h ++ t)
    Just (_, _) -> error "findAndSeparateOrs found something other than an Or!"
    Nothing -> Or (map flattenOrs l)

toDNF :: Logic a -> Logic a
toDNF = flattenOrs . pushAnds . removeNots

add :: (Eq a) => Integer -> [(a, Integer)] -> a -> [(a, Integer)]
add n ((s,v):t) el
 | s == el = (s,v + n):t
 | otherwise = (s,v):(add n t el)
add _ [] _ = [] 

toEquation :: Eq a => [a] -> Logic a -> [Rational]
toEquation syms (Eq (LE l1 l2)) = (map toRational v) ++ [c]
  where csyms = zip syms $ repeat 0
        pl1 = map getVar $ (filter isPVar l1) ++ (filter isNVar l2)
        nl1 = map getVar $ (filter isPVar l2) ++ (filter isNVar l1)
        csyms2 = foldl' (add 1) csyms pl1
        csyms3 = foldl' (add (-1)) csyms2 nl1
        (_,v) = unzip csyms3
        cp = sum (map getConst $ filter isConst l2)
        cn = sum (map getConst $ filter isConst l1)
        c = toRational (cp - cn)
toEquation _ _ = error "Wrong format in toEquation"

toMatrix :: Eq a => Logic a -> ([[Rational]], [Integer], [Maybe a])
toMatrix l@(And c) = (map (toEquation symbols) c, [1..genericLength c], allSymbols)
 where symbols = collectVars l
       allSymbols = (map Just $ symbols) ++ [Nothing]
toMatrix (Eq c) = toMatrix (And [Eq c])
toMatrix _ = error "Wrong format in toMatrix"

getFirstResult :: [Maybe [(Maybe a, Integer)]] -> Maybe [(a, Integer)]
getFirstResult [] = Nothing
getFirstResult ((Nothing):t) = getFirstResult t
getFirstResult ((Just x):_) = Just $ [(e, n) | (Just e, n) <- x]

solveLogic :: Eq a => Logic a -> Maybe [(a, Integer)]
solveLogic l = getFirstResult res
  where
   res = map (solveLEInt . toMatrix) options
   options = case toDNF l of
               Or r -> r
               r@(And _) -> [r]
               r@(Eq _) -> [And [r]]
               r@(Not _) -> [And [r]]


