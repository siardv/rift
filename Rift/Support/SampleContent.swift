/// the "try an example" pair (fr-13, sdd §7.3): one real content change plus
/// formatting-only differences at every ladder level, so the first run shows
/// the verdict, the accounting, and the reading view all at once.
/// escapes are deliberate — trailing spaces, curly quotes, and hard wraps must
/// survive editors and source formatting byte-exactly
enum SampleContent {
    static let left: String =
        "Rift measures the gap between two texts.\n"
        + "It reads them the way you would,\n"
        + "not the way a terminal does.\n"
        + "\n"
        + "\n"
        + "\u{201C}What actually changed?\u{201D} is the only question a diff needs to answer.\n"
        + "\n"
        + "Everything else is layout:  wrapping, indentation, stray spaces.\n"
        + "\n"
        + "The colour of the verdict stays calm either way. \n"
        + "Every difference set aside is counted, listed, and one tap away.\n"

    static let right: String =
        "Rift measures the gap between two texts. It reads them the way you would, not the way a terminal does.\n"
        + "\n"
        + "\"What actually changed?\" is the only question a diff needs to answer.\n"
        + "\n"
        + "Everything else is layout: wrapping, indentation, stray spaces.\n"
        + "\n"
        + "The color of the verdict stays calm either way.\n"
        + "Every difference set aside is counted, listed, and one tap away.\n"
}
