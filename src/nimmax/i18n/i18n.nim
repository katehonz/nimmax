import std/[tables, strutils, parsecfg, streams]
import ../core/types, ../core/context

type
  Translator* = ref object
    language*: string
    translations*: TableRef[string, TableRef[string, string]]

  TranslationDB* = ref object
    defaultLanguage*: string
    data*: TableRef[string, TableRef[string, TableRef[string, string]]]

proc newTranslationDB*(defaultLanguage = "en"): TranslationDB =
  TranslationDB(
    defaultLanguage: defaultLanguage,
    data: newTable[string, TableRef[string, TableRef[string, string]]]()
  )

proc loadTranslation*(db: TranslationDB, filename: string) =
  var f = newFileStream(filename)
  if f.isNil:
    return

  var
    p: CfgParser
    currentSection = ""

  p.open(filename, f)
  defer: p.close()

  while true:
    let ev = p.next()
    case ev.kind
    of cfgEof:
      break
    of cfgSectionStart:
      currentSection = ev.section
      if not db.data.hasKey(currentSection):
        db.data[currentSection] = newTable[string, TableRef[string, string]]()
    of cfgKeyValuePair:
      if currentSection.len > 0:
        let lang = ev.key
        let translation = ev.value
        if not db.data[currentSection].hasKey(lang):
          db.data[currentSection][lang] = newTable[string, string]()
        db.data[currentSection][lang][currentSection] = translation
    of cfgError:
      discard

proc translate*(db: TranslationDB, key: string, language = ""): string =
  let lang = if language.len > 0: language else: db.defaultLanguage
  if db.data.hasKey(key) and db.data[key].hasKey(lang):
    let translations = db.data[key][lang]
    if translations.hasKey(key):
      return translations[key]
  return key

proc setLanguage*(ctx: Context, language: string): Translator =
  Translator(
    language: language,
    translations: newTable[string, TableRef[string, string]]()
  )

proc Tr*(translator: Translator, key: string): string =
  if translator.translations.hasKey(key) and translator.translations[key].hasKey(translator.language):
    return translator.translations[key][translator.language]
  return key
