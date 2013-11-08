
-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : portable
--
-- Provides overloaded pitch literals.
--
-------------------------------------------------------------------------------------

module Music.Dynamics.Literal (
        DynamicsL(..),
        IsDynamics(..),

        pppppp, ppppp, pppp, ppp, pp, _p, 
        mp, mf, 
        _f, ff, fff, ffff, fffff, ffffff,
        
        sffz, sfz, fz, rfz, fp
  ) where

-- | 
-- Dynamics literal.
--
-- First value is start value, second is end value.
-- 
-- * @(Just x, Nothing)@ is a constant dynamic of @x@
-- * @(Just x, Just y)@ is a dynamic varying from @x@ to @y@
-- * @(Nothing, Just y)@ is a dynamic varying from the previous level to @y@
-- * @(Nothing, Nothing)@ is a dynamic varying from the previous level to the next.
--
-- For levels, we use @-0.5@ for /mp/, @0.5@ for /mf/ and add or remove one for each level.
-- @0@ is an unspecified middle level dynamic.
--
newtype DynamicsL = DynamicsL { getDynamicsL :: (Maybe Double, Maybe Double) }
    deriving (Eq, Show, Ord)

-- Like Num can be expressed using arabic numerals, instances
-- of IsDynamics can be expressed using Western pitch names (c, c sharp, c flat etc)    
class IsDynamics a where
    fromDynamics :: DynamicsL -> a

instance IsDynamics DynamicsL where
    fromDynamics = id

instance IsDynamics a => IsDynamics (Maybe a) where
    fromDynamics = Just . fromDynamics

instance IsDynamics Double where
    fromDynamics (DynamicsL (Just x, _)) = x
    fromDynamics (DynamicsL (Nothing, _)) = error "IsDynamics Double: No dynamics"


pppppp, ppppp, pppp, ppp, pp, _p, mp, mf, _f, ff, fff, ffff, fffff, ffffff ::  IsDynamics a => a
sffz, sfz, fz, rfz, fp ::  IsDynamics a => a

pppppp  = fromDynamics $ DynamicsL (Just $ -6.5, Nothing)
ppppp   = fromDynamics $ DynamicsL (Just $ -5.5, Nothing)
pppp    = fromDynamics $ DynamicsL (Just $ -4.5, Nothing)
ppp     = fromDynamics $ DynamicsL (Just $ -3.5, Nothing)
pp      = fromDynamics $ DynamicsL (Just $ -2.5, Nothing)
_p      = fromDynamics $ DynamicsL (Just $ -1.5, Nothing)
mp      = fromDynamics $ DynamicsL (Just $ -0.5, Nothing)
mf      = fromDynamics $ DynamicsL (Just $  0.5, Nothing)
_f      = fromDynamics $ DynamicsL (Just $  1.5, Nothing)
ff      = fromDynamics $ DynamicsL (Just $  2.5, Nothing)
fff     = fromDynamics $ DynamicsL (Just $  3.5, Nothing)
ffff    = fromDynamics $ DynamicsL (Just $  4.5, Nothing)
fffff   = fromDynamics $ DynamicsL (Just $  5.5, Nothing)
ffffff  = fromDynamics $ DynamicsL (Just $  6.5, Nothing)

sffz    = error "Not supported yet"
sfz     = error "Not supported yet"
fz      = error "Not supported yet"
rfz     = error "Not supported yet"
fp      = error "Not supported yet"
