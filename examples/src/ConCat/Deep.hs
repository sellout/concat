{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MonadComprehensions #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-unused-imports #-} -- TEMP

#include "ConCat/Ops.inc"

-- | Simple feed-forward deep learning

module ConCat.Deep where

import Prelude hiding (zipWith)

import GHC.TypeLits ()
import GHC.Generics (Par1(..),(:*:)(..),(:.:)(..))

import Data.Key
import Data.Vector.Sized (Vector)
import Data.NumInstances.Function ()
import Data.Functor.Rep (Representable)

import ConCat.Misc
import ConCat.Additive
import ConCat.AltCat (forkF,joinPF,scale,crossF,jamPF,(:--*),linearApp',linearApp)
import ConCat.Orphans ()
import ConCat.RAD (gradR)

{--------------------------------------------------------------------
    Simple linear algebra
--------------------------------------------------------------------}

infixl 7 *^, <.>, >.<

-- | Scale a vector
scaleV, (*^) :: (Functor a, Num s) => s -> a s -> a s
s *^ v = scale s <$> v
scaleV = (*^)
{-# INLINE (*^) #-}

-- From AltCat:
--
-- -- | Generalized matrix
-- infixr 1 :--*
-- type (p :--* q) u = q (p u)

-- | Linear map representation ("matrix")
infixr 1 --*
type a --* b = (a :--* b) R

infixr 1 -->
type a --> b = a R -> b R

-- dot' :: (h (s -> s)) -> (h s -> s)
-- dot' = joinPF

-- | Inner product
dotV,(<.>) :: (Summable a, Additive s, Num s) => a s -> a s -> s
(<.>) = joinPF . fmap scale
dotV = (<.>)
{-# INLINE (<.>) #-}
{-# INLINE dotV #-}

-- | Outer product
outerV, (>.<) :: (Functor a, Functor b, Num s) => a s -> b s -> a (b s)
a >.< b = (*^ b) <$> a
outerV = (>.<)
{-# INLINE (>.<) #-}
{-# INLINE outerV #-}

-- (*^ b)       :: s -> b s
-- (*^ b) <$> a :: a s -> a (b s)

linear' :: (Summable a, Summable b, Additive v)
        => (a :--* b) (u -> v) -> (a u -> b v)
linear' = linearApp'
{-# INLINE linear' #-}

-- | Apply a linear map
linear :: (Summable a, Summable b, Additive s, Num s)
       => (a :--* b) s -> (a s -> b s)
linear = linearApp
{-# INLINE linear #-}

-- linear :: (a --* b) -> (a --> b)

-- NOTE: linear' and linear' depend on the bogus IxCoproductPCat (->) instance
-- in ConCat.Category. Okay if we translate to another category. I'll find a
-- more principled way.

type Bump h = h :*: Par1

bump :: Num s => a s -> Bump a s
bump a = a :*: Par1 1

-- | Affine map representation
infixr 1 :--+
type (a :--+ b) s = (Bump a :--* b) s

-- | Affine map over R
infixr 1 --+
type a --+ b = (a :--+ b) R
               -- Bump a --* b

-- | Affine application
affine :: (Summable a, Summable b, Additive s, Num s)
       => (a :--+ b) s -> (a s -> b s)
affine m = linear m . bump
{-# INLINE affine #-}

--        m        :: b (Bump a s)
-- linear m        :: Bump a s -> b s
-- linear m . bump :: a s -> b s

-- TODO: Is there an affine counterpart to linear'?

normSqr :: (Summable n, Additive s, Num s) => n s -> s
normSqr u  = u <.> u
{-# INLINE normSqr #-}

-- | Distance squared
distSqr :: (Summable n, Additive s, Num s) => n s -> n s -> s
distSqr u v = normSqr (zipWith (-) u v)
{-# INLINE distSqr #-}

-- The normSqr and distSqr definitions rely on Num instances on functions.

{--------------------------------------------------------------------
    Learning
--------------------------------------------------------------------}

-- | Affine followed by RELUs.
affRelu :: (Summable a, Summable b) => (a --+ b) -> (a --> b)
affRelu = (result.result.fmap) (max 0) affine
{-# INLINE affRelu #-}

-- affRelu l = fmap (max 0) . affine l

errSqr :: Summable b => a R :* b R -> (a --> b) -> R
errSqr (a, b) h = distSqr b (h a)
{-# INLINE errSqr #-}

errGrad :: Summable b => (p -> a --> b) -> a R :* b R -> Unop p
errGrad h sample = gradR (errSqr sample . h)
{-# INLINE errGrad #-}

infixr 9 @.
(@.) :: (p -> b -> c) -> (q -> a -> b) -> (p :* q -> a -> c)
(f @. g) (p,q) = f p . g q
{-# INLINE (@.) #-}

{--------------------------------------------------------------------
    Examples
--------------------------------------------------------------------}

lr1 :: (Summable a, Summable b) => (a --+ b)  ->  (a --> b)
lr1 = affRelu
{-# INLINE lr1 #-}

lr2 :: (Summable a, Summable b, Summable c)
    => (b --+ c) :* (a --+ b)  ->  (a --> c)
lr2 = affRelu @. affRelu
{-# INLINE lr2 #-}

lr3 :: (Summable a, Summable b, Summable c, Summable d)
    => (c --+ d) :* (b --+ c) :* (a --+ b)  ->  (a --> d)
lr3 = affRelu @. affRelu @. affRelu
{-# INLINE lr3 #-}