{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}

{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}

module SAWScript.AST where

import SAWScript.Unify

import Control.Monad
import Data.List

import Data.Foldable hiding (concat)
import Data.Traversable

type MPType = Maybe (Mu (Type :+: Poly))
type PType = Mu (Type :+: Poly)
type LType = Mu (Type :+: Logic)
type CType = Mu Type

-- Expr Level {{{

data Module a = Module
  { declarations :: [TopStmt a]
  , mainBlock    :: [BlockStmt Context a]
  }
  deriving (Functor,Foldable,Traversable)

instance Show a => Show (Module a) where
  show (Module ds mb) = (intercalate "\n" $ map show ds) ++ "\n\n" ++ (intercalate "\n" $ map show mb)

data TopStmt a
  = Import      Name               (Maybe [Name])   (Maybe Name)
  | TypeDef     Name               PType
  | TopTypeDecl Name               PType
  | TopLet      [(Name,Expr a)]
  deriving (Functor,Foldable,Traversable)

instance Show a => Show (TopStmt a) where
  show s = case s of
    Import n ns qn   -> case qn of
      Nothing -> "import " ++ n ++ maybe "" (\ns -> " (" ++ intercalate ", " ns ++ ")") ns
      Just q  -> "import qualified " ++ n ++ maybe "" (\ns -> " (" ++ intercalate ", " ns ++ ")") ns ++ " as " ++ q
    TypeDef n pt     -> "type " ++ n ++ " = " ++ show pt
    TopTypeDecl n pt -> n ++ " :: " ++ show pt
    TopLet nes       -> intercalate "\n" $ map (\(n,e) -> n ++ " = " ++ show e) nes

data BlockStmt c a
  = Bind          (Maybe Name)     c (Expr a)
  | BlockTypeDecl Name             PType
  | BlockLet      [(Name,Expr a)]
  deriving (Functor,Foldable,Traversable)

instance Show a => Show (BlockStmt Context a) where
  show s = case s of
    Bind mn c e        -> case mn of
      Nothing -> show e
      Just n  -> n ++ " <- " ++ show e
    BlockTypeDecl n pt -> "let " ++ n ++ " :: " ++ show pt
    BlockLet nes       -> "let " ++ (intercalate "; " $ map (\(n,e) -> n ++ " = " ++ show e) nes)

data Expr a
  -- Constants
  = Bit         Bool                          a
  | Quote       String                        a
  | Z           Integer                       a
  -- Structures
  | Array       [Expr a]                      a
  | Block       [BlockStmt Context a]         a
  | Tuple       [Expr a]                      a
  | Record      [(Name, Expr a)]              a
  -- Accessors
  | Index       (Expr a)           (Expr a)   a
  | Lookup      (Expr a)           Name       a
  -- LC
  | Var         Name                          a
  | Function    Name     a         (Expr a)   a
  | Application (Expr a)           (Expr a)   a
  -- Sugar
  | LetBlock    [(Name,Expr a)]    (Expr a)
  deriving (Functor,Foldable,Traversable)

instance Show a => Show (Expr a) where
  show e = case e of
    Bit b mt            -> showMaybe mt $ if b then "'1" else "'0"
    Quote s mt          -> showMaybe mt $ show s
    Z i mt              -> showMaybe mt $ show i
    Array es mt         -> showMaybe mt $ "[" ++ (intercalate ", " $ map show es) ++ "]"
    Block ss mt         -> showMaybe mt $ intercalate "\n" $ ("do" : map (("  " ++) . show) ss)
    Tuple es mt         -> showMaybe mt $ "(" ++ (intercalate ", " $ map show es) ++ ")"
    Record nes mt       -> showMaybe mt $ "{" ++ (intercalate ", " $ map (\(n,e) -> n ++ " = " ++ show e) nes) ++ "}"
    Index ar ix mt      -> showMaybe mt $ "(" ++ show ar ++ " ! " ++ show ix ++ ")"
    Lookup r f mt       -> showMaybe mt $ "(" ++ show r ++ "." ++ show f ++ ")"
    Var n mt            -> showMaybe mt $ n
    Function an at b mt -> showMaybe mt $ "(\\" ++ an ++ " :: " ++ show at ++ " -> " ++ show b ++ ")"
    Application f v mt  -> showMaybe mt $ "(" ++ show f ++ " " ++ show v ++ ")"
    LetBlock nes b      -> "(let " ++ (intercalate "; " $ map (\(n,e) -> n ++ " = " ++ show e) nes) ++ " in " ++ show b ++ ")"

showMaybe :: Show a => a -> String -> String
showMaybe t s = "(" ++ s ++ " :: " ++ show t ++ ")"

type Name = String
data Context = Context deriving (Eq,Show)

-- }}}

-- Type {{{

data Type a
  -- Constants
  = Bit'
  | Z'
  | Quote'
  -- Structures
  | Array'       a
  | Block'       Context    a
  | Tuple'       [a]
  | Record'      [(Name,a)]
  -- LC
  | Function'    a          a
  | Syn          String
  deriving (Show,Functor,Foldable,Traversable)

data Poly a = Poly Name
instance Functor Poly where fmap f (Poly n) = Poly n

data Logic a = LVar Int
instance Functor Logic where fmap f (LVar i) = LVar i

type MPType = Maybe (Mu (Type :+: Poly))
type PType = Mu (Type :+: Poly)
type LType = Mu (Type :+: Logic)
type CType = Mu Type

instance Render Type where
  render t = case t of
    Bit'            -> "Bit"
    Z'              -> "Z"
    Quote'          -> "Quote"
    Array' t l      -> "[" ++ show l ++ "]" ++ show t
    Block' c t      -> show c ++ " " ++ show t
    Tuple' ts       -> "(" ++ (intercalate ", " $ map show ts) ++ ")"
    Record' fts     -> "{" ++ (intercalate ", " $ map (\(n,t)-> n ++ " :: " ++ show t) fts) ++ "}"
    Function' at bt -> "(" ++ show at ++ " -> " ++ show bt ++ ")"
    Syn n           -> n

instance Render Poly where render (Poly n) = n

instance Render Logic where render (LVar i) = "_." ++ show i

-- }}}

-- Functor instances {{{

instance Functor Module where
  fmap f m = m { declarations = map (fmap f) $ declarations m
               , main         = map (fmap f) $ main m
               }

instance Functor TopStmt where
  fmap f s = case s of
    Import n mns mn -> Import n mns mn
    TypeDef n t     -> TypeDef n t
    TopTypeDecl n t -> TopTypeDecl n t
    TopLet binds    -> let (ns,es) = unzip binds in
                         TopLet $ zip ns $ map (fmap f) es

instance Functor BlockStmt where
  fmap f s = case s of
    Bind n e          -> Bind n $ fmap f e
    BlockTypeDecl n t -> BlockTypeDecl n t
    BlockLet binds    -> let (ns,es) = unzip binds in
                           BlockLet $ zip ns $ map (fmap f) es

instance Functor Expr where
  fmap f e = case e of
    Bit b a                   -> Bit b $ f a
    Quote s a                 -> Quote s $ f a
    Z i a                     -> Z i $ f a
    Array es a                -> Array (map (fmap f) es) $ f a
    Block ss a                -> Block (map (fmap f) ss) $ f a
    Tuple es a                -> Tuple (map (fmap f) es) $ f a
    Record nes a              -> let (ns,es) = unzip nes in
                                   Record (zip ns $ map (fmap f) es) $ f a
    Index ar ix a             -> Index (fmap f ar) (fmap f ix) $ f a
    Lookup rc fl a            -> Lookup (fmap f rc) fl $ f a
    Var n a                   -> Var n $ f a
    Function argn argt body a -> Function argn (f argt) (fmap f body) $ f a
    Application fn v a        -> Application (fmap f fn) (fmap f v) $ f a
    LetBlock binds body       -> let (ns,es) = unzip binds in
                                   LetBlock (zip ns $ map (fmap f) es) (fmap f body)

instance Functor Type where
  fmap f t = case t of
    Bit'              -> Bit'
    Z'                -> Z'
    Quote'            -> Quote'
    Array' t' l       -> Array' (f t') l
    Block' c t'       -> Block' c (f t')
    Tuple' ts'        -> Tuple' (map f ts')
    Record' fts'      -> let (ns,ts') = unzip fts' in
                           Record' (zip ns $ map f ts')
    Function' at' bt' -> Function' (f at') (f bt')
    Syn n             -> Syn n

-- }}}

-- Equal Instances {{{

instance Equal Type where
  equal t1 t2 = case (t1,t2) of
    (Bit',Bit')                               -> True
    (Z',Z')                                   -> True
    (Quote',Quote')                           -> True
    (Array' t1',Array' t2')                   -> t1' == t2'
    (Block' c1 t1',Block' c2 t2')             -> c1 == c2 && t1' == t2'
    (Tuple' ts1',Tuple' ts2')                 -> ts1' == ts2'
    (Record' fts1',Record' fts2')             -> fts1' == fts2'
    (Function' at1' bt1',Function' at2' bt2') -> at1' == at2' && bt1' == bt2'
    (Syn n1,Syn n2)                           -> n1 == n2
    _                                         -> False
-- }}}

-- Render {{{
instance Render Type where
  render t = case t of
    Bit'            -> "Bit"
    Z'              -> "Z"
    Quote'          -> "Quote"
    Array' t        -> "[" ++ show t ++ "]"
    Block' c t      -> "(Block " ++ show c ++ " " ++ show t ++ ")"
    Tuple' ts       -> "(" ++ (intercalate ", " $ map show ts) ++ ")"
    Record' fts     -> "{" ++ (intercalate ", " $ map (\(n,t)-> n ++ " :: " ++ show t) fts) ++ "}"
    Function' at bt -> "(" ++ show at ++ " -> " ++ show bt ++ ")"
    Syn n           -> n
-- }}}

-- Uni {{{
instance Uni Type where
  uni t1 t2 = case (t1,t2) of
    (Array' t1',Array' t2')                   -> unify t1' t2'
    (Block' c1 t1',Block' c2 t2')             -> guard (c1 == c2) >> unify t1' t2'
    (Tuple' ts1',Tuple' ts2')                 -> zipWithMP_ unify ts1' ts2'
    (Record' fts1',Record' fts2')             -> do conj [ disj [ unify x y | (nx,x) <- fts1', nx == ny ] | (ny,y) <- fts2' ]
                                                    conj [ disj [ unify y x | (ny,y) <- fts2', nx == ny ] | (nx,x) <- fts1' ]
    (Function' at1' bt1',Function' at2' bt2') -> unify at1' at2' >> unify bt1' bt2'
    _                                         -> mzero
-- }}}

-- Operators {{{

bit :: (Type :<: f) => Mu f
bit = inject Bit'

quote :: (Type :<: f) => Mu f
quote = inject Quote'

z :: (Type :<: f) => Mu f
z = inject Z'

array :: (Type :<: f) => Mu f ->Mu f
array t = inject $ Array' t

block :: (Type :<: f) => Context -> Mu f -> Mu f
block c t = inject $ Block' c t

tuple :: (Type :<: f) => [Mu f] -> Mu f
tuple ts = inject $ Tuple' ts

record :: (Type :<: f) => [(Name,Mu f)] -> Mu f
record fts = inject $ Record' fts

function :: (Type :<: f) => Mu f -> Mu f -> Mu f
function at bt = inject $ Function' at bt

syn :: (Type :<: f) => String -> Mu f
syn n = inject $ Syn n

-- }}}

-- }}}

-- Poly {{{

data Poly a = Poly Name deriving (Show,Functor,Foldable,Traversable)

instance Render Poly where render (Poly n) = n

instance Equal Poly where
  equal (Poly n1) (Poly n2) = n1 == n2

instance Uni Poly where
  uni (Poly n1) (Poly n2) = guard (n1 == n2)

poly :: (Poly :<: f) => String -> Mu f
poly n = inject $ Poly n

-- }}}

class Functor f => Decorated f where
  decor :: f a -> a

instance Decorated Expr where
  decor e = case e of
    Bit _ t           -> t
    Quote _ t         -> t
    Z _ t             -> t
    Array _ t         -> t
    Block _ t         -> t
    Tuple _ t         -> t
    Record _ t        -> t
    Index _ _ t       -> t
    Lookup _ _ t      -> t
    Var _ t           -> t
    Function _ _ _ t  -> t
    Application _ _ t -> t
    LetBlock _ e      -> decor e

context :: BlockStmt c a -> Maybe c
context s = case s of
  Bind _ c _ -> Just c
  _          -> Nothing

-- Tests {{{

m1 :: Module MPType
m1 = Module
  { declarations =
    [ Import "Foo" Nothing Nothing
    , TypeDef "Test" bit
    , TopTypeDecl "map4" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b"))))
    , TopTypeDecl "a1" (array z)
    , TopTypeDecl "plus1" (function z z)
    ]
  , mainBlock = 
    [ Bind Nothing Context (Application (Var "map4" Nothing) (Var "plus1" Nothing) Nothing)
    --[ Bind Nothing Context (Var "map4" Nothing)
    ]
  }

m1b :: Module MPType
m1b = Module
  { declarations =
    [ Import "Foo" Nothing Nothing
    , TypeDef "Test" bit
    , TopTypeDecl "map4" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b"))))
    , TopTypeDecl "a1" (array z)
    , TopTypeDecl "plus1" (function (syn "Test") (syn "Test"))
    ]
  , mainBlock = 
    [ Bind Nothing Context (Application (Var "map4" Nothing) (Var "plus1" Nothing) Nothing)
    ]
  }

m1c :: Module MPType
m1c = Module
  { declarations =
    [ Import "Foo" Nothing Nothing
    , TypeDef "Test" bit
    , TopTypeDecl "map4" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b"))))
    , TopTypeDecl "a1" (array (syn "Test"))
    , TopTypeDecl "plus1" (function (syn "Test") (syn "Test"))
    ]
  , mainBlock = 
    [ Bind Nothing Context (Application (Application (Var "map4" Nothing) (Var "plus1" Nothing) Nothing) (Var "a1" Nothing) Nothing)
    ]
  }

m2 :: Module MPType
m2 = Module
  { declarations =
    [ Import "Foo" Nothing Nothing
    , TypeDef "Test" bit
    , TopTypeDecl "map4" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b"))))
    , TopTypeDecl "a1" (array z)
    , TopTypeDecl "plus1" (function z z)
    ]
  , mainBlock = 
    [ Bind Nothing Context (Var "map4" (Just (function (poly "a") (poly "a"))))
    ]
  }

m2b :: Module MPType
m2b = Module
  { declarations =
    [ TopTypeDecl "map4" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b"))))
    ]
  , mainBlock = 
    [ Bind Nothing Context (Var "map4" (Just (function (poly "a") (poly "b"))))
    ]
  }

m3 :: Module MPType
m3 = Module
  { declarations = []
  , mainBlock = [ Bind Nothing Context (Bit True Nothing) ]
  }

m4 :: Module MPType
m4 = Module
  { declarations = [ TopTypeDecl "a" bit ]
  , mainBlock =
    [ Bind Nothing Context (Var "a" Nothing) ]
  }

m5 :: Module MPType
m5 = Module
  { declarations =
    [ TopLet [("a", (Bit True Nothing))] ]
  , mainBlock =
    [ Bind Nothing Context (Var "a" Nothing) 
    ]
  }

m6 :: Module MPType
m6 = Module
  { declarations = [ TopTypeDecl "a" (function (function (poly "a") (poly "b")) (function (array (poly "a")) (array (poly "b")))) ]
  , mainBlock = [ Bind Nothing Context (Var "a" Nothing) ]
  }

-- }}}

