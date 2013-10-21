{-# LANGUAGE 
     NoMonomorphismRestriction
   , FlexibleContexts 
   , RankNTypes #-}

-- remove unix dependency in music-dynamics-literal

import qualified Music.Lilypond as L
import Music.Lilypond hiding (Rest, rest, Time, Key)
import Music.Lilypond.IO
import Music.Lilypond.Pitch
import Data.AdditiveGroup

import Text.Parsec
--import Text.Parsec.ByteString.Lazy
import Text.Parsec.String
import qualified Text.Parsec.Token as P
-- import Text.Parsec.Language (haskellDef) -- haskellDef replaced below to generalize from String/Identity
--import Text.ParserCombinators.Parsec.Number -- cabal install parsec-numbers 
import NumberGen -- my generalization of parsec-numbers to ParsecT

import Data.Ratio
import Numeric.Natural hiding (natural)
-- import Data.Word -- consider as alternative to Natrual?
import Data.Fixed
import Data.Char
import Data.List hiding (transpose)
import qualified Data.Map as M
import Data.Maybe
import Control.Applicative hiding (many, (<|>))
import Control.Arrow
import Control.Monad
import Control.Monad.Reader
import Control.Monad.Identity
import GHC.Exts

main = either print engrave =<< parseFromFile transcript (f ++ ".dt") -- dt = 'degreeTranscript format'
  where f = "tears"
        engrave = writeParts f
        debug = writeFile (f ++ ".debug") . show

writeParts f t = do 
  mapM_ (writeMusic f . fix . lily t) v
  writeScore f t
  where v = concat $ (\xs -> 
              if length xs > 1
                 then (\(x@(Voice _ i@(Instrument s _ _)),n) -> x{instrument = i{name = s ++ "(" ++ show n ++ ")"}}) <$> zip xs [1..]
                 else xs)
            <$> groupWith (show . instrument) (voices t)
        fix (a,b,c,d) = (a ^+^ d,b,c)

writeScore f t = writeMusic f (each {- single -}, ex $ head ms, i $ head ms)
  where ms = (\c -> lily t $ Voice c $ Instrument "score" concert Nothing) <$> (nub $ columnVoice <$> voices t)
        m  (x,_,_,_) = x
        ex (_,x,_,_) = x
        i  (_,_,x,_) = x
        p  (_,_,_,x) = x
        single = (m $ head ms) ^+^ Simultaneous True (p <$> ms)
        each = New "StaffGroup" Nothing $ Simultaneous False $ s <$> ms
        s m' = New "Staff" Nothing $ m m' ^+^ p m'         

concert = PitchClass C Natural

--lily :: Transcription -> Voice -> (Music,String,String)
lily t v = (m,ex,i,p)
  where m =     Clef Treble
            ^+^ L.Time (time t) 4
            ^+^ L.Key (transpose (key t) outKey Natural First) (mode $ key t)
        p = Relative (Pitch (concert, Just $ 2 + fromMaybe 0 (oct $ instrument v))) (sumV (lily' (time t) (key t) outKey <$> getVoice (columnVoice v) <$> sections t))
        ex = " \\header { title = " ++ show (title t) ++ " composer = " ++ show (composer t) ++ " instrument = " ++ show i ++ "}"
        outKey = iKey $ instrument v
        i = show $ instrument v

getVoice :: Column -> Section -> [Element]
getVoice c s = reverse $ foldl f [] $ notes s
  where f done ns = g (nub $ duration <$> ns) done $ filter ((c == ) . columnElement) ns
        g []      _          _   = error "impossible -- no duration"
        g (_:_:_) _          _   = error "impossible -- more than one duration on a line"
        g _       []         []  = error "first line of section must have note for every voice" -- should we assume rest or tie from previous section?  what if first section?        
        g [d]     (now:done) []  = now{duration = d + duration now} : done
        g _       done       [n] = n : done
        g _       _          _   = error "impossible -- two notes in one row in same column!?"

lily' :: Time -> Key -> PitchClass -> [Element] -> Music
lily' t inKM outK s = Mark Nothing ^+^ Sequential [sumV $ lily'' inKM outK <$> bars (Duration $ (fromIntegral t) / 4) s] ^+^ Bar Double

bars :: Duration -> [Element] -> [Element]
bars t ns = bars' t 0 ns []
bars' _ _  []     out = reverse out
bars' t t' (n:ns) out = bars' t t'' ns' $ this : out
        where (t'', this, ns') = if now <= t 
                then (mod' now t, n    ,          ns) 
                else (0         , first, second : ns)
              now  = t' + duration n
              (first,second) = splitDur (t - t') n
              splitDur d (Element (DegreeNote a g o _) c d') = (Element (DegreeNote a g o True) c d, Element (DegreeNote a g Nothing False) c $ d' - d)
              splitDur d (Element  Rest                c d') = (Element  Rest                   c d, Element  Rest                          c $ d' - d)

lily'' :: Key -> PitchClass -> Element -> Music
lily'' _    _    (Element  Rest                _ dur) = L.Rest                                    (Just dur) []
lily'' inKM outK (Element (DegreeNote a d o t) _ dur) = Note (NotePitch (Pitch (pc', o)) Nothing) (Just dur) [Tie | t] -- silly hlint comprehension trick
        where pc' = transpose inKM outK a d

transpose :: Key -> PitchClass -> Accidental -> Degree -> PitchClass
transpose (Key inK m) outK = tone $ Key (step (head $ steps outK inK) concert) m

step (0,0) = id
step (0,h) = step (0,h-1) . inc Half
step (w,h) = step (w-1,h) . inc Whole

-- poor strategy, how fix?
steps k1 k2 = filter ((k2 ==) . flip step k1) [(w,h) | w <- [0..5], h <- [0..2]]

diff d1 d2 = pos d2 - pos d1
pos = fromJust . flip elemIndex enum
get xs = (xs !!) . flip mod (length xs)

enum :: (Enum a, Bounded a) => [a]
enum = [minBound .. maxBound]
degrees = enum :: [Degree]
whiteKeys = enum :: [WhiteKey]

data Step = Whole | Half deriving Show
major = [Whole, Whole, Half, Whole, Whole, Whole, Half]
minor = modal 6 major
modal n s = take (length s) $ drop (n-1) $ cycle s

scale k = tone k Natural <$> enum

tone :: Key -> Accidental -> Degree -> PitchClass
tone (Key pc m) acc d = getNote pc (pos d) acc $ 
        case m of Major -> major
                  Minor -> minor

getNote :: PitchClass -> Int -> Accidental -> [Step] -> PitchClass
getNote (PitchClass w a) 0 acc _         = PitchClass w $ enum !! ((pos a) + diff Natural acc)
getNote p                d acc (s:steps) = getNote (inc s p) (d - 1) acc steps

inc s (PitchClass w a) = PitchClass w' a'
        where w' = get enum $ (pos w) + 1
              a' = fix s $ get major $ pos w -- depends on WhiteKeys as [C .. B]
              fix Half Whole = adj (-) a
              fix Whole Half = adj (+) a
              fix _     _    = a -- args are equal
              adj op n = enum !! op (pos n) 1 -- op can't be sectioned to pointfree this?

data Transcription = Transcription {
        title    :: Title 
      , composer :: Composer 
      , year     :: Year 
      , key      :: Key 
      , time     :: Time 
      , start    :: Start 
      , pattern  :: Pattern 
      , voices   :: [Voice]
      , sections :: [Section]
  } deriving (Eq,Show)
data Voice = Voice {
    columnVoice :: Column
  , instrument :: Instrument
  } deriving (Eq,Show) 
data Instrument = Instrument {
      name :: String 
    , iKey :: PitchClass 
    , oct  :: Octave 
  } deriving (Eq)
instance Show Instrument where
  show (Instrument s k oct) = s ++ " in " ++ show k
data Key = Key { 
        pc   :: PitchClass 
      , mode :: Mode
  } deriving (Eq,Show)
type Time = Natural
type Start = Ratio Natural
type Pattern = String
type Title = String
type Composer = String
type Year = String
data Section = Section {
        label :: Char 
      , notes :: [[Element]]
  } deriving (Eq)
instance Show Section 
  where show (Section l n) = "\nlabel: " ++ pure l ++ "\n" ++ unlines (show <$> n)
data DegreeNote = DegreeNote Accidental Degree Octave Tie | Rest
  deriving (Eq,Show)
data Element = Element {
    note     :: DegreeNote
  , columnElement   :: Column
  , duration :: Duration
  } deriving (Eq)
instance Show Element
  where show (Element n c d) = (show n) ++ " " ++ (show $ getDuration d) ++ " col: " ++ (show c)
data Degree = First | Second | Third | Fourth | Fifth | Sixth | Seventh
  deriving (Eq,Show,Enum,Bounded)
type Octave = Maybe Int
type Tie = Bool

lexxer = P.makeTokenParser haskellDef'
whiteSpace = P.whiteSpace lexxer
-- natural' = toNatural . (fromInteger :: Integer -> Word) <$> P.natural lexxer
natural = fromIntegral <$> P.natural lexxer
naturalOrFloat = P.naturalOrFloat lexxer

-- stolen from http://hackage.haskell.org/package/parsec-3.1.3/docs/src/Text-Parsec-Language.html#haskellStyle
-- since haskellDef locks us in to Strings and Identity
haskellDef' :: P.GenLanguageDef s u m
haskellDef' = P.LanguageDef
                { P.commentStart   = "{-"
                , P.commentEnd     = "-}"
                , P.commentLine    = "--"
                , P.nestedComments = True               
                , P.identStart     = undefined -- letter
                , P.identLetter    = undefined -- alphaNum <|> oneOf "_'"
                , P.opStart        = undefined -- P.opLetter haskellDef''
                , P.opLetter       = undefined -- oneOf ":!#$%&*+./<=>?@\\^|-~"
                , P.reservedOpNames= undefined -- []
                , P.reservedNames  = undefined -- []
                , P.caseSensitive  = undefined -- True                
                }

type PT m b = (Stream s m Char, Monad m, Functor m) => ParsecT s u m b -- how remove Char constraint from s?
type P b = forall m. PT m b

-- a $> b = a >> return b
($>) = flip (<$)

--tryChoice :: [Parser a] -> Parser a
tryChoice = choice . (try <$>)

line = manyTill anyChar newline -- (newline <|> (eof >> return '\n'))

--transcript :: P Transcription
transcript = do 
  title    <- line
  composer <- line
  year     <- line
  key      <- keyP
  time     <- timeP
  start    <- startP
  pattern  <- patternP
  voices   <- many1 voiceP
  sections <- runPTR (columnVoice <$> voices) (many1 sectionP) 
  whiteSpace >> eof
  return $ Transcription title composer year key time start pattern voices sections
        
-- thanks saizan@#haskell!
mapParsecT :: (Functor m, Functor n, Monad m, Monad n) => (forall a. m a -> n a) -> ParsecT s u m a -> ParsecT s u n a
mapParsecT f p = mkPT $ \ s -> f $ (f <$>) <$> runParsecT p s -- how pointfree s?

runPTR :: r -> ParsecT s u (Reader r) a -> Parsec s u a
runPTR r = mapParsecT $ flip runReaderT r -- how pointfree r?

voiceP :: P Voice
voiceP = try $ whiteSpace >> Voice <$> col (/= 1) "voice spec can't be in column 1 (which is for durations)" <*> instrumentP

instrumentP :: P Instrument
instrumentP = Instrument <$> manyTill anyChar (try $ string " in ") <*> pitchClassP <*> octaveP

pitchClassP :: P PitchClass
pitchClassP = whiteSpace >> PitchClass <$> whiteKeyP <*> accidentalP

whiteKeyP, whiteKeyP' :: P WhiteKey
whiteKeyP' = read . pure . toUpper <$> tryChoice (char <$> ws ++ (toLower <$> ws)) -- <?> "WhiteKey"
  where ws = head . show <$> whiteKeys
whiteKeyP = tryChoice (enum' <$> enum)
        where enum' s = s <$ tryChoice (char <$> [u, toLower u])
               where u = head $ show s

modeP :: P Mode
modeP = whiteSpace >> tryChoice [ string "min" $> Minor
                                , string "maj" $> Major
                                ] -- <?> "Mode"

keyP :: P Key
keyP = whiteSpace >> Key <$> pitchClassP <*> modeP

timeP :: P Time
timeP = whiteSpace >> natural

--startP :: P Start
startP = frac

patternP :: P Pattern
patternP = whiteSpace >> many1 letter

--sectionP :: (MonadReader [Column] m) => PT m Section
sectionP = try $ Section <$> (whiteSpace >> letter <* whiteSpace) <*> sepEndBy1 parts whiteSpace

--parts :: (MonadReader [Column] m) => PT m [Element]
parts = do
   col (== 1) "duration must fall at beginning of line in column 1"
   d <- durationP
   ns <- many1 $ tryChoice [degreeNoteP, restP]
   return $ (\(c,x) -> Element x c d) <$> ns

degreeNoteP,restP :: (MonadReader [Column] m) => PT m (Column, DegreeNote)
degreeNoteP = w' $ DegreeNote <$> accidentalP <*> degreeP <*> octaveP <*> pure False
restP = w' $ Rest <$ char 'R'

--w' :: (Eq a, Num a, MonadReader [a] m) => P b -> PT m (a, b)
w' = (((,) <$> (whiteSpace >> col (/= 1) e) <* (flip col e' . flip elem =<< lift ask) ) <*>) 
  where e  = "first item in line must be duration, not note"
        e' = "non-part column, do you have some naughty tabs?"

w :: (Eq a, Num a, MonadReader [a] m) => b -> PT m (a, b)
w d = do
  c <- whiteSpace >> col (/= 1) "first item in line must be duration, not note"
  cs <- ask
  col (`elem` cs) "non-part column, do you have some naughty tabs?"
  return (c,d)

col :: (Num b) => (b -> Bool) -> String -> P b
col f s = do 
   c <- fromIntegral . sourceColumn <$> getPosition
   if f c then return c
          else unexpected s

degreeP :: P Degree
degreeP = fromJust . flip M.lookup m <$> tryChoice (string <$> M.keys m)
  where m = M.fromList $ zip (show <$> [1..]) degrees

accidentalP :: P Accidental
accidentalP = option Natural $ tryChoice [
    DoubleFlat  <$ string "bb" -- must try first!
  , Flat        <$ char   'b'
  , Sharp       <$ char   '#'
  , DoubleSharp <$ char   'x'
  ] -- <?> "Accidental"

octaveP :: P Octave
octaveP = optionMaybe $ tryChoice [ 
               countChar '+'
  , negate <$> countChar '-'
  ]

countChar = (length <$>) . many1 . char

--durationP :: P Duration
durationP = (/ 4) <$> frac

--frac :: (Fractional b) => P b
--frac = (fromRational . toRational ||| fromRational . toRational) <$> (whiteSpace >> naturalOrFloat) -- requires leading 0.
frac = fromRational . toRational <$> floating3 False
