/// Glue that lets Japanese copy break only where the copy is written in
/// phrases.
///
/// ICU, which Flutter uses to find line-break opportunities, breaks Japanese
/// anywhere: the script is written without spaces and every character is a
/// legal break. Flutter adds no word or phrase segmentation of its own, so at
/// 200% text a line turned inside a word — 「プロフィ／ール」,
/// 「いま、ひ／ま？」, 「知／らせよう」.
///
/// [wrapPhrases] takes the phrases a string is written in and returns it with
/// exactly the break opportunities the copy wants:
///
/// * between the characters of one phrase it puts a WORD JOINER (U+2060), so
///   the phrase cannot be split;
/// * between two phrases it puts a ZERO WIDTH SPACE (U+200B), the place a line
///   may turn.
///
/// Both are formatting characters rather than glyphs: they take no space and
/// draw nothing, so the copy still reads the same. They are still part of the
/// string, though, so a widget that displays the result must pass
/// [plainPhrases] of it as its semantics label: that is the copy a reader
/// hears, without characters nobody can see.
///
/// Pass phrases, never individual characters: callers decide where the phrases
/// are.
String wrapPhrases(Iterable<String> phrases) => phrases
    // `runes`, not `split('')`: a phrase may contain characters outside the
    // BMP, and joining their surrogate halves would be corruption.
    .map((phrase) => phrase.runes.map(String.fromCharCode).join(_wordJoiner))
    .join(_phraseBreak);

/// The plain copy of a string built by [wrapPhrases]: the same text without
/// the invisible break characters, as it is written in the source.
///
/// Use it for anything that is not laid out as text — most importantly the
/// semantics label of the widget showing the wrapped string.
String plainPhrases(String wrapped) =>
    wrapped.replaceAll(_wordJoiner, '').replaceAll(_phraseBreak, '');

/// U+2060 WORD JOINER: the line may not break at this position.
const _wordJoiner = '\u2060';

/// U+200B ZERO WIDTH SPACE: the line may break at this position.
const _phraseBreak = '\u200b';
