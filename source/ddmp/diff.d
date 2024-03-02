/*
 * Copyright 2008 Google Inc. All Rights Reserved.
 * Copyright 2013-2014 Jan Krüger. All Rights Reserved.
 * Author: fraser@google.com (Neil Fraser)
 * Author: anteru@developer.shelter13.net (Matthaeus G. Chajdas)
 * Author: jan@jandoe.de (Jan Krüger)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Diff Match and Patch
 * http://code.google.com/p/google-diff-match-patch/
 */
module ddmp.diff;

import ddmp.util;

import std.array;
import std.conv;
import std.datetime : SysTime, Clock, UTC;
import std.exception : enforce;
import std.string : indexOf, endsWith, startsWith;
import std.uni;
import std.utf : toUTF16, toUTF8;
import std.range : ElementEncodingType;
import std.regex;
import std.algorithm : min, max;
import std.digest.sha;
import std.traits : isSomeString;
import core.time;


Duration diffTimeout = 1.seconds;
int DIFF_EDIT_COST = 4;

alias Diff = DiffT!string;

/**
* Compute and return the source text (all equalities and deletions).
* @param diffs List of DiffT objects.
* @return Source text.
*/
Str diff_text1(Str)(DiffT!(Str)[] diffs) {
    auto text = appender!Str();
    foreach ( d; diffs ) {
        if (d.operation != Operation.INSERT) {
            text.put(d.text);
        }
    }
    return text[];
}

/**
* Compute and return the destination text (all equalities and insertions).
* @param diffs List of DiffT objects.
* @return Destination text.
*/
Str diff_text2(Str)(DiffT!(Str)[] diffs) {
    auto text = appender!Str();
    foreach ( d; diffs ) {
        if (d.operation != Operation.DELETE) {
            text.put(d.text);
        }
    }
    return text[];
}


/**
 * Compute the Levenshtein distance; the number of inserted, deleted or
 * substituted characters.
 * @param diffs List of DiffT objects.
 * @return Number of changes.
 */
int levenshtein(Str)(DiffT!(Str)[] diffs) {
    int levenshtein = 0;
    int insertions = 0;
    int deletions = 0;
    foreach ( d ; diffs ) {
        final switch (d.operation) {
          case Operation.INSERT:
            insertions += d.text.length;
            break;
          case Operation.DELETE:
            deletions += d.text.length;
            break;
          case Operation.EQUAL:
            // A deletion and an insertion is one substitution.
            levenshtein += max(insertions, deletions);
            insertions = 0;
            deletions = 0;
            break;
        }
    }
    levenshtein += max(insertions, deletions);
    return levenshtein;
}


/**
 * Crush the diff into an encoded string which describes the operations
 * required to transform text1 into text2.
 * E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
 * Operations are tab-separated.  Inserted text is escaped using %xx
 * notation.
 * @param diffs Array of DiffT objects.
 * @return Delta text.
 */
Str toDelta(Str)(in DiffT!(Str)[] diffs)
{
    import std.range : walkLength;
    import std.format : formattedWrite;
    import std.uri : encode;
    auto text = appender!string;
    foreach (aDiffT; diffs) {
        final switch (aDiffT.operation) {
            case Operation.INSERT:
                text.formattedWrite("+%s\t", encode(aDiffT.text).replace("%20", " "));
                break;
            case Operation.DELETE:
                text.formattedWrite("-%s\t", aDiffT.text.walkLength);
                break;
            case Operation.EQUAL:
                text.formattedWrite("=%s\t", aDiffT.text.walkLength);
                break;
        }
    }
    string delta = text.data;
    if (delta.length != 0) {
        // Strip off trailing tab character.
        delta = delta[0 .. $-1];
        delta = unescapeForEncodeUriCompatibility(delta);
    }
    return delta;
}

/**
 * Given the original text1, and an encoded string which describes the
 * operations required to transform text1 into text2, comAdde the full diff.
 * @param text1 Source string for the diff.
 * @param delta Delta text.
 * @return Array of DiffT objects or null if invalid.
 * @throws ArgumentException If invalid input.
 */
DiffT!(Str)[] fromDelta(Str)(Str text1, Str delta)
{
    import std.algorithm;
    import std.range;
    import std.string : format;
    import std.uri : decodeComponent;

    auto diffs = appender!(DiffT!(Str)[]);
    foreach (token; delta.splitter("\t".to!Str)) {
        if (token.length == 0) {
            // Blank tokens are ok (from a trailing \t).
            continue;
        }
        // Each token begins with a one character parameter which specifies the
        // operation of this token (delete, insert, equality).
        Str param = token[1 .. $];
        switch (token[0]) {
            case '+':
                // decode would change all "+" to " "
                param = param.replace("+".to!Str, "%2b".to!Str);
                param = decodeComponent(param);
                //} catch (UnsupportedEncodingException e) {
                //  // Not likely on modern system.
                //  throw new Error("This system does not support UTF-8.", e);
                //} catch (IllegalArgumentException e) {
                //  // Malformed URI sequence.
                //  throw new IllegalArgumentException(
                //      "Illegal escape in diff_fromDelta: " + param, e);
                //}
                diffs ~= DiffT!Str(Operation.INSERT, param);
                break;
            case '-': // Fall through.
            case '=':
                int n;
                try {
                    n = param.to!int;
                } catch (ConvException e) {
                    throw new Exception("Invalid number in diff_fromDelta: " ~ param);
                }
                enforce (n >= 0, "Negative number in diff_fromDelta: " ~ param);

                string text;
                enforce (n <= text1.walkLength, "Delta length larger than source text length.");
                text = text1.takeExactly(n).array.to!string;
                text1.popFrontN(n);
                if (token[0] == '=') {
                    diffs ~= DiffT!Str(Operation.EQUAL, text);
                } else {
                    diffs ~= DiffT!Str(Operation.DELETE, text);
                }
                break;
            default:
                // Anything else is an error.
                throw new Exception(
                "Invalid diff operation in diff_fromDelta: " ~ token[0]);
        }
    }
    if (text1.length > 0)
        throw new Exception("Delta length smaller than source text length.");
    return diffs.data;
}

alias LinesToCharsResult = LinesToCharsResultT!string;

struct LinesToCharsResultT(Str) {
    Str text1;
    Str text2;
    Str[] uniqueStrings;
    bool opEquals()(auto ref const LinesToCharsResultT!Str other) const {
        return text1 == other.text1 &&
               text2 == other.text2 &&
               uniqueStrings == other.uniqueStrings;
    }
}

LinesToCharsResultT!Str linesToChars(Str)(Str text1, Str text2) {
    size_t[Str] lineHash;
    LinesToCharsResultT!Str res;
    res.uniqueStrings = [""];
    res.text1 = linesToCharsMunge(text1, res.uniqueStrings, lineHash);
    res.text2 = linesToCharsMunge(text2, res.uniqueStrings, lineHash);
    return res;
}

/**
 * Given a block of text, decompose it into:
 * - Unique lines of text.
 * - A hash from lines of text to their index in the unique lines.
 * Finally, it returns a string with each UTF-16 character representing the unique line index for
 * each line of text in the original block of text.
 */
Str linesToCharsMunge(Str)(Str text, ref Str[] lines, ref size_t[Str] linehash)
if (isSomeString!Str) {
    sizediff_t lineStart = 0;
    sizediff_t lineEnd = -1;
    Str line;
    static if (is(ElementEncodingType!Str : char)) {
      size_t lineLimit = 0x80;
    } else {
      size_t lineLimit = 0xD800;
    }
    enforce(lines.length < lineLimit, "Algorithm unique line limit exceeded for "
        ~ Str.stringof ~ ". string may use 127 lines, wstring/dstring may use 55295 lines.");
    auto chars = appender!Str();
    while( lineEnd+1 < text.length ){
        lineEnd = text.indexOfAlt("\n".to!Str, lineStart);
        if( lineEnd == -1 ) lineEnd = text.length - 1;
        line = text[lineStart..lineEnd + 1];
        lineStart = lineEnd + 1;

        if (auto pv = line in linehash) {
            chars ~= cast(ElementEncodingType!Str)*pv;
        } else {
            lines ~= line;
            linehash[line] = lines.length - 1;
            // Using UTF-16, only values up to 0xD7FF (55295) can be represented before
            // encoding errors or multi-byte encodings are applied.
            chars ~= cast(ElementEncodingType!Str)(lines.length -1);
        }
    }
    return chars[];
}

/**
 * Reverses the process of [linesToChars] by interpretting each UTF-16 character as an index into
 * linesArray, and assembles the indexed lines into a block of text.
 */
void charsToLines(Str)(DiffT!Str[] diffs, Str[] lineArray)
if (isSomeString!Str) {
    foreach (ref d; diffs) {
        auto str = appender!Str();
        foreach (ElementEncodingType!Str ch; d.text) {
            str.put(lineArray[ch]);
        }
        d.text = str[];
    }
}

/// The character offset should be aware of unicode, otherwise, the common prefix can end up
/// splitting a single character's bytes.
size_t commonPrefix(Str)(Str text1, Str text2)
if (isSomeString!Str) {
    auto n = min(text1.length, text2.length);
    foreach (i; 0 .. n)
        if (text1[i] != text2[i])
            return i;
    return n;
}

size_t commonSuffix(Str)(Str text1, Str text2)
if (isSomeString!Str) {
    auto n = min(text1.length, text2.length);
    foreach (i; 1 .. n+1)
        if (text1[$-i] != text2[$-i])
            return i-1;
    return n;
}

/**
* Determine if the suffix of one string is the prefix of another.
* @param text1 First string.
* @param text2 Second string.
* @return The number of characters common to the end of the first
*     string and the start of the second string.
*/
size_t commonOverlap(Str)(Str text1, Str text2)
if (isSomeString!Str) {
    // Cache the text lengths to prevent multiple calls.
    auto text1_length = text1.length;
    auto text2_length = text2.length;
    // Eliminate the null case.
    if (text1_length == 0 || text2_length == 0) return 0;

    // Truncate the longer string.
    if (text1_length > text2_length) {
        text1 = text1[$ - text2_length .. $];
    } else if (text1_length < text2_length) {
        text2 = text2[0 .. text1_length];
    }
    auto text_length = min(text1_length, text2_length);
    // Quick check for the worst case.
    if (text1 == text2) {
        return text_length;
    }

    // Start by looking for a single character match
    // and increase length until no match is found.
    // Performance analysis: http://neil.fraser.name/news/2010/11/04/
    int best = 0;
    int length = 1;
    while (true) {
        Str pattern = text1[text_length - length .. $];
        auto found = text2.indexOf(pattern);
        if (found == -1) {
            return best;
        }
        length += found;
        if (found == 0 || text1[text_length - length .. $] == text2[0 .. length]) {
            best = length;
            length++;
        }
    }
}

/**-
* The data structure representing a diff is a List of DiffT objects:
* {DiffT(Operation.DELETE, "Hello"), DiffT(Operation.INSERT, "Goodbye"),
*  DiffT(Operation.EQUAL, " world.")}
* which means: delete "Hello", add "Goodbye" and keep " world."
*/
enum Operation {
    DELETE,
    INSERT,
    EQUAL
}


/**
* Struct representing one diff operation.
*/
struct DiffT(Str)
if (isSomeString!Str) {
    Operation operation;
    Str text;

    this(Operation operation, Str text)
    {
        this.operation = operation;
        this.text = text;
    }

    string toString()
    {
        //string prettyText = text.replace('\n', '\u00b6');
        string op;
        final switch(operation)  {
            case Operation.DELETE:
                op = "DELETE"; break;
            case Operation.INSERT:
                op = "INSERT"; break;
            case Operation.EQUAL:
                op = "EQUAL"; break;
        }
        return "DiffT!" ~ Str.stringof ~ "(" ~ op ~ ",\"" ~ toUTF8(text) ~ "\")";
    }

    bool opEquals(const DiffT other) const
    {
        return operation == other.operation && text == other.text;
    }
}


/**
 * Find the differences between two texts.
 * Run a faster, slightly less optimal diff.
 * This method allows the 'checklines' of diff_main() to be optional.
 * Most of the time checklines is wanted, so default to true.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @return List of DiffT objects.
 */
DiffT!(Str)[] diff_main(Str)(Str text1, Str text2)
{
    return diff_main(text1, text2, true);
}

/**
 * Find the differences between two texts.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @param checklines Speedup flag.  If false, then don't run a
 *     line-level diff first to identify the changed areas.
 *     If true, then run a faster slightly less optimal diff.
 * @return List of DiffT objects.
 */
DiffT!(Str)[] diff_main(Str)(Str text1, Str text2, bool checklines)
{
    // Set a deadline by which time the diff must be complete.
    SysTime deadline;
    if (diffTimeout <= 0.seconds) {
        deadline = SysTime.max;
    } else {
        deadline = Clock.currTime(UTC()) + diffTimeout;
    }
    return diff_main(text1, text2, checklines, deadline);
}

/**
 * Find the differences between two texts.  Simplifies the problem by
 * stripping any common prefix or suffix off the texts before diffing.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @param checklines Speedup flag.  If false, then don't run a
 *     line-level diff first to identify the changed areas.
 *     If true, then run a faster slightly less optimal diff.
 * @param deadline Time when the diff should be complete by.  Used
 *     internally for recursive calls.  Users should set DiffTTimeout
 *     instead.
 * @return List of DiffT objects.
 */
DiffT!(Str)[] diff_main(Str)(Str text1, Str text2, bool checklines, SysTime deadline)
{
    DiffT!(Str)[] diffs;
    if( text1 == text2 ){
        if( text1.length != 0 ) diffs ~= DiffT!Str(Operation.EQUAL, text1);
        return diffs;
    }

    auto pos = commonPrefix(text1, text2);
    auto prefix = text1[0 .. pos];
    text1 = text1[pos .. $];
    text2 = text2[pos .. $];

    pos = commonSuffix(text1, text2);
    auto suffix = text1[$ - pos .. $];
    text1 = text1[0 .. $ - pos];
    text2 = text2[0 .. $ - pos];

    // Compute the diff on the middle block.
    diffs = computeDiffTs(text1, text2, checklines, deadline);

      // Restore the prefix and suffix.
    if( prefix.length != 0 ) {
        diffs.insert(0, [DiffT!Str(Operation.EQUAL, prefix)]);
    }
    if( suffix.length != 0 ) {
        diffs ~= DiffT!Str(Operation.EQUAL, suffix);
    }

    cleanupMerge(diffs);
    return diffs;
}


alias HalfMatch = HalfMatchT!string;

struct HalfMatchT(Str) {
    Str prefix1;
    Str suffix1;
    Str suffix2;
    Str prefix2;
    Str commonMiddle;

    bool opEquals()(auto ref const HalfMatchT!Str other) const {
        return prefix1 == other.prefix1 &&
               suffix1 == other.suffix1 &&
               prefix2 == other.prefix2 &&
               suffix2 == other.suffix2;
    }
}

/*
 * Do the two texts share a Substring which is at least half the length of
 * the longer text?
 * This speedup can produce non-minimal diffs.
 * @param text1 First string.
 * @param text2 Second string.
 * @return Five element String array, containing the prefix of text1, the
 *     suffix of text1, the prefix of text2, the suffix of text2 and the
 *     common middle.  Or null if there was no match.
 */
bool halfMatch(Str)(Str text1, Str text2, out HalfMatchT!Str halfmatch){
    if (diffTimeout <= 0.seconds) {
        // Don't risk returning a non-optimal diff if we have unlimited time.
        return false;
    }
    Str longtext = text1.length > text2.length ? text1 : text2;
    Str shorttext = text1.length > text2.length ? text2 : text1;
    if( longtext.length < 4 || shorttext.length * 2 < longtext.length ) return false; //pointless
    HalfMatchT!Str hm1;
    HalfMatchT!Str hm2;
    auto is_hm1 = halfMatchI(longtext, shorttext, (longtext.length + 3) / 4, hm1);
    auto is_hm2 = halfMatchI(longtext, shorttext, (longtext.length + 1) / 2, hm2);
    HalfMatchT!Str hm;
    if( !is_hm1 && !is_hm2 ){
        return false;
    } else if( !is_hm2  ){
        hm = hm1;
    } else if( !is_hm1 ){
        hm = hm2;
    } else {
        hm = hm1.commonMiddle.length > hm2.commonMiddle.length ? hm1 : hm2;
    }

    if( text1.length > text2.length ) {
        halfmatch = hm;
        return true;
    }
    halfmatch.prefix1 = hm.prefix2;
    halfmatch.suffix1 = hm.suffix2;
    halfmatch.prefix2 = hm.prefix1;
    halfmatch.suffix2 = hm.suffix1;
    halfmatch.commonMiddle = hm.commonMiddle;
    return true;
}


bool halfMatchI(Str)(Str longtext, Str shorttext, sizediff_t i, out HalfMatchT!Str hm){
    auto seed = longtext.substr(i, longtext.length / 4);
    sizediff_t j = -1;
    Str best_common;
    Str best_longtext_a;
    Str best_longtext_b;
    Str best_shorttext_a;
    Str best_shorttext_b;
    while( j < cast(sizediff_t)shorttext.length && ( j = shorttext.indexOfAlt(seed, j + 1)) != -1 ){
        auto prefixLen = commonPrefix(longtext[i .. $], shorttext[j .. $]);
        auto suffixLen = commonSuffix(longtext[0 .. i], shorttext[0 .. j]);
        if( best_common.length < suffixLen + prefixLen ) {
            best_common = shorttext.substr(j - suffixLen, suffixLen) ~ shorttext.substr(j, prefixLen);
            best_longtext_a = longtext[0 .. i - suffixLen];
            best_longtext_b = longtext[i + prefixLen .. $];
            best_shorttext_a = shorttext[0 .. j - suffixLen];
            best_shorttext_b = shorttext[j + prefixLen .. $];
        }
    }
    if( best_common.length * 2 >= longtext.length ) {
        hm.prefix1 = best_longtext_a;
        hm.suffix1 = best_longtext_b;
        hm.prefix2 = best_shorttext_a;
        hm.suffix2 = best_shorttext_b;
        hm.commonMiddle = best_common;
        return true;
    } else {
        return false;
    }
}


/**
 * Find the differences between two texts.  Assumes that the texts do not
 * have any common prefix or suffix.
 * @param text1 Old string to be diffed.
 * @param text2 New string to be diffed.
 * @param checklines Speedup flag.  If false, then don't run a
 *     line-level diff first to identify the changed areas.
 *     If true, then run a faster slightly less optimal diff.
 * @param deadline Time when the diff should be complete by.
 * @return List of DiffT objects.
 */
DiffT!(Str)[] computeDiffTs(Str)(Str text1, Str text2, bool checklines, SysTime deadline)
{
    DiffT!(Str)[] diffs;

    if( text1.length == 0 ){
        diffs ~= DiffT!Str(Operation.INSERT, text2);
        return diffs;
    }
    if( text2.length == 0 ){
        diffs ~= DiffT!Str(Operation.DELETE, text1);
        return diffs;
    }

    auto longtext = text1.length > text2.length ? text1 : text2;
    auto shorttext = text1.length > text2.length ? text2 : text1;
    auto i = longtext.indexOf(shorttext);
    if( i != -1 ){
        Operation op = (text1.length > text2.length) ? Operation.DELETE : Operation.INSERT;
        diffs ~= DiffT!Str(op, longtext[0 .. i]);
        diffs ~= DiffT!Str(Operation.EQUAL, shorttext);
        diffs ~= DiffT!Str(op, longtext[i + shorttext.length .. $]);
        return diffs;
    }

    if( shorttext.length == 1 ){
        diffs ~= DiffT!Str(Operation.DELETE, text1);
        diffs ~= DiffT!Str(Operation.INSERT, text2);
        return diffs;
    }
    HalfMatchT!Str hm;
    auto is_hm = halfMatch(text1, text2, hm);
    if( is_hm ){
        auto diffs_a = diff_main(hm.prefix1, hm.prefix2, checklines, deadline);
        auto diffs_b = diff_main(hm.suffix1, hm.suffix2, checklines, deadline);

        diffs = diffs_a;
        diffs ~= DiffT!Str(Operation.EQUAL, hm.commonMiddle);
        diffs ~= diffs_b;
        return diffs;
    }

    if( checklines && text1.length > 100 && text2.length > 100 ){
        return diff_lineMode(text1, text2, deadline);
    }

    return bisect(text1, text2, deadline);
}

DiffT!(Str)[] diff_lineMode(Str)(Str text1, Str text2, SysTime deadline)
{
    auto b = linesToChars(text1, text2);

    auto diffs = diff_main(b.text1, b.text2, false, deadline);

    charsToLines(diffs, b.uniqueStrings);
    cleanupSemantic(diffs);

    diffs ~= DiffT!Str(Operation.EQUAL, "");
    auto pointer = 0;
    auto count_delete = 0;
    auto count_insert = 0;
    Str text_delete;
    Str text_insert;
    while( pointer < diffs.length ){
        final switch( diffs[pointer].operation ) {
            case Operation.INSERT:
                count_insert++;
                text_insert ~= diffs[pointer].text;
                break;
            case Operation.DELETE:
                count_delete++;
                text_delete ~= diffs[pointer].text;
                break;
            case Operation.EQUAL:
                if( count_delete >= 1 && count_insert >= 1 ){

                    diffs.remove(pointer - count_delete - count_insert,
                                 count_delete + count_insert);

                    pointer = pointer - count_delete - count_insert;

                    auto a = diff_main(text_delete, text_insert, false, deadline);
                    diffs.insert(pointer, a);
                    pointer += a.length;
                }
                count_insert = 0;
                count_delete = 0;
                text_delete = "";
                text_insert = "";
                break;
        }
        pointer++;
    }
    diffs.remove(diffs.length - 1);
    return diffs;
}

DiffT!(Str)[] bisect(Str)(Str text1, Str text2, SysTime deadline)
{
    auto text1_len = text1.length;
    auto text2_len = text2.length;
    auto max_d = (text1_len + text2_len + 1) / 2;
    auto v_offset = max_d;
    auto v_len = 2 * max_d;
    sizediff_t[] v1;
    sizediff_t[] v2;
    for( auto x = 0; x < v_len; x++ ){
        v1 ~= -1;
        v2 ~= -1;
    }
    v1[v_offset + 1] = 0;
    v2[v_offset + 1] = 0;
    auto delta = text1_len - text2_len;
    bool front = (delta % 2 != 0);
    auto k1start = 0;
    auto k1end = 0;
    auto k2start = 0;
    auto k2end = 0;
    for( auto d = 0; d < max_d; d++ ){
        // Bail out if deadline is reached.
        if (Clock.currTime(UTC()) > deadline) {
            break;
        }

        for( auto k1 = -d + k1start; k1 <= d - k1end; k1 += 2 ){
            auto k1_offset = v_offset + k1;
            sizediff_t x1;
            if( k1 == -d || k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1] ) {
                x1 = v1[k1_offset + 1];
            } else {
                x1 = v1[k1_offset - 1] + 1;
            }
            auto y1 = x1 - k1;
            while( x1 < text1_len && y1 < text2_len && text1[x1] == text2[y1] ){
                x1++;
                y1++;
            }
            v1[k1_offset] = x1;
            if( x1 > text1_len) {
                k1end += 2;
            } else if( y1 > text2_len ){
                k1start += 2;
            } else if( front ){
                auto k2_offset = v_offset + delta - k1;
                if( k2_offset >= 0 && k2_offset < v_len && v2[k2_offset] != -1) {
                    auto x2 = text1_len - v2[k2_offset];
                    if( x1 >= x2 ) return bisectSplit(text1, text2, x1, y1, deadline);
                }
            }
        }
        for( auto k2 = -d + k2start; k2 <= d - k2end; k2 += 2) {
            auto k2_offset = v_offset + k2;
            sizediff_t x2;
            if (k2 == -d || k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1]) {
                x2 = v2[k2_offset + 1];
            } else {
                x2 = v2[k2_offset - 1] + 1;
            }
            auto y2 = x2 - k2;
            while( x2 < text1_len && y2 < text2_len
                    && text1[text1_len - x2 - 1]
                    == text2[text2_len - y2 - 1] ){
                x2++;
                y2++;
            }
            v2[k2_offset] = x2;
            if (x2 > text1_len) {
                // Ran off the left of the graph.
                k2end += 2;
            } else if (y2 > text2_len) {
                // Ran off the top of the graph.
                k2start += 2;
            } else if (!front) {
                auto k1_offset = v_offset + delta - k2;
                if (k1_offset >= 0 && k1_offset < v_len && v1[k1_offset] != -1) {
                    auto x1 = v1[k1_offset];
                    auto y1 = v_offset + x1 - k1_offset;
                    // Mirror x2 onto top-left coordinate system.
                    x2 = text1_len - v2[k2_offset];
                    if (x1 >= x2) {
                        // Overlap detected.
                        return bisectSplit(text1, text2, x1, y1, deadline);
                    }
                }
            }
        }
    }
    DiffT!(Str)[] diffs;
    diffs ~= DiffT!Str(Operation.DELETE, text1);
    diffs ~= DiffT!Str(Operation.INSERT, text2);
    return diffs;
}


DiffT!(Str)[] bisectSplit(Str)(Str text1, Str text2, sizediff_t x, sizediff_t y, SysTime deadline)
{
    auto text1a = text1[0 .. x];
    auto text2a = text2[0 .. y];
    auto text1b = text1[x .. $];
    auto text2b = text2[y .. $];

    DiffT!(Str)[] diffs = diff_main(text1a, text2a, false, deadline);
    DiffT!(Str)[] diffsb = diff_main(text1b, text2b, false, deadline);
    diffs ~= diffsb;
    return diffs;
}

void cleanupSemantic(Str)(ref DiffT!(Str)[] diffs)
{
    bool changes = false;
    size_t[] equalities;

    Str last_equality = null;
    size_t pointer = 0;
    size_t length_insertions1 = 0;
    size_t length_deletions1 = 0;
    size_t length_insertions2 = 0;
    size_t length_deletions2 = 0;

    while( pointer < diffs.length) {
        if( diffs[pointer].operation == Operation.EQUAL ){
            equalities ~= pointer;
            length_insertions1 = length_insertions2;
            length_deletions1 = length_deletions2;
            length_insertions2 = 0;
            length_deletions2 = 0;
            last_equality = diffs[pointer].text;
        } else {
            if( diffs[pointer].operation == Operation.INSERT ){
                length_insertions2 += diffs[pointer].text.length;
            } else {
                length_deletions2 += diffs[pointer].text.length;
            }

            if( last_equality !is null &&
                (last_equality.length <= max(length_insertions1, length_deletions1))
                && (last_equality.length <= max(length_insertions2, length_deletions2)))
            {
                // Duplicate record.
                diffs.insert(equalities[$-1], [DiffT!Str(Operation.DELETE, last_equality)]);
                diffs[equalities[$-1]+1] = DiffT!Str(Operation.INSERT, diffs[equalities[$-1]+1].text);

                // Throw away the equality we just deleted.
                equalities.length--;
                if (equalities.length > 0) {
                    // Throw away the previous equality (it needs to be reevaluated).
                    equalities.length--;
                }
                equalities.assumeSafeAppend();

                pointer = equalities.length > 0 ? equalities[$-1] : -1;
                length_insertions1 = 0;
                length_deletions1 = 0;
                length_insertions2 = 0;
                length_deletions2 = 0;
                last_equality = null;
                changes = true;
            }
        }
        pointer++;
    }

    if( changes ) {
        cleanupMerge(diffs);
    }
    cleanupSemanticLossless(diffs);

    // Find any overlaps between deletions and insertions.
    // e.g: <del>abcxxx</del><ins>xxxdef</ins>
    //   -> <del>abc</del>xxx<ins>def</ins>
    // e.g: <del>xxxabc</del><ins>defxxx</ins>
    //   -> <ins>def</ins>xxx<del>abc</del>
    // Only extract an overlap if it is as big as the edit ahead or behind it.

    pointer = 1;
    while( pointer < diffs.length ){
        if( diffs[pointer - 1].operation == Operation.DELETE &&
            diffs[pointer].operation == Operation.INSERT) {
            auto deletion = diffs[pointer - 1].text;
            auto insertion = diffs[pointer].text;
            auto overlap_len1 = commonOverlap(deletion, insertion);
            auto overlap_len2 = commonOverlap(insertion, deletion);
            if( overlap_len1 >= overlap_len2 ){
                if( overlap_len1 * 2 >= deletion.length ||
                    overlap_len1 * 2 >= insertion.length) {
                    //Overlap found.
                    //Insert an equality and trim the surrounding edits.
                    diffs.insert(pointer, [DiffT!Str(Operation.EQUAL, insertion[0 .. overlap_len1])]);
                    diffs[pointer - 1].text = deletion[0 .. $ - overlap_len1];
                    diffs[pointer + 1].text = insertion[overlap_len1 .. $];
                    pointer++;
                }
            } else {
                if( overlap_len2 * 2 >= deletion.length ||
                    overlap_len2 * 2 >= insertion.length) {
                    diffs.insert(pointer, [DiffT!Str(Operation.EQUAL, deletion[0 .. overlap_len2])]);

                    diffs[pointer - 1].operation = Operation.INSERT;
                    diffs[pointer - 1].text = insertion[0 .. $ - overlap_len2];
                    diffs[pointer + 1].operation = Operation.DELETE;
                    diffs[pointer + 1].text = deletion[overlap_len2 .. $];
                    pointer++;
                }
            }
            pointer++;
        }
        pointer++;
    }
}

/**
 * Look for single edits surrounded on both sides by equalities
 * which can be shifted sideways to align the edit to a word boundary.
 * e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
 * @param diffs List of DiffT objects.
 */
void cleanupSemanticLossless(Str)(ref DiffT!(Str)[] diffs)
{
    auto pointer = 1;
    // Intentionally ignore the first and last element (don't need checking).
    while( pointer < cast(sizediff_t)(diffs.length) - 1 ){
        if( diffs[pointer-1].operation == Operation.EQUAL &&
            diffs[pointer+1].operation == Operation.EQUAL) {
            // This is a single edit surrounded by equalities.
            auto equality1 = diffs[pointer-1].text;
            auto edit = diffs[pointer].text;
            auto equality2 = diffs[pointer+1].text;

            // First, shift the edit as far left as possible
            auto commonOffset = commonSuffix(equality1, edit);
            if( commonOffset > 0 ){
                auto commonString = edit[$ - commonOffset .. $];
                equality1 = equality1[0 .. $ - commonOffset];
                edit = commonString ~ edit[0 .. $ - commonOffset];
                equality2 = commonString ~ equality2;
            }

            // Second, step character by character right,
            // looking for the best fit.
            auto best_equality1 = equality1;
            auto best_edit = edit;
            auto best_equality2 = equality2;
            auto best_score = cleanupSemanticScore(equality1, edit) + cleanupSemanticScore(edit, equality2);
            while( edit.length != 0 && equality2.length != 0 && edit[0] == equality2[0]){
                equality1 ~= edit[0];
                edit =  edit[1 .. $] ~ equality2[0];
                equality2 = equality2[1 .. $];
                auto score = cleanupSemanticScore(equality1, edit) + cleanupSemanticScore(edit, equality2);
                // The >= encourages trailing rather than leading whitespace on
                // edits.
                if (score >= best_score) {
                    best_score = score;
                    best_equality1 = equality1;
                    best_edit = edit;
                    best_equality2 = equality2;
                }
            }

            if( diffs[pointer-1].text != best_equality1 ){
                // We have an improvement, save it back to the diff.
                if( best_equality1.length != 0) {
                    diffs[pointer-1].text = best_equality1;
                } else {
                    diffs.remove(pointer - 1);
                    pointer--;
                }
                diffs[pointer].text = best_edit;
                if( best_equality2.length != 0 ){
                    diffs[pointer+1].text = best_equality2;
                } else {
                    diffs.remove(pointer + 1);
                    pointer--;
                }
            }
        }
        pointer++;
    }
}




/**
 * Reorder and merge like edit sections.  Merge equalities.
 * Any edit section can move as sizediff_t as it doesn't cross an equality.
 * @param diffs List of DiffT objects.
 */
void cleanupMerge(Str)(ref DiffT!(Str)[] diffs) {
    diffs ~= DiffT!(Str)(Operation.EQUAL, "");
    size_t pointer = 0;
    size_t count_delete = 0;
    size_t count_insert = 0;
    Str text_delete;
    Str text_insert;
    while(pointer < diffs.length) {
        final switch(diffs[pointer].operation){
            case Operation.INSERT:
                count_insert++;
                text_insert ~= diffs[pointer].text;
                pointer++;
                break;
            case Operation.DELETE:
                count_delete++;
                text_delete ~= diffs[pointer].text;
                pointer++;
                break;
            case Operation.EQUAL:
                // Upon reaching an equality, check for prior redundancies.
                if (count_delete + count_insert > 1) {
                    if (count_delete != 0 && count_insert != 0) {
                        // Factor out any common prefixes.
                        if (auto commonlength = commonPrefix(text_insert, text_delete)) {
                            if (pointer > count_delete + count_insert &&
                                diffs[pointer - count_delete - count_insert - 1].operation
                                    == Operation.EQUAL)
                            {
                                diffs[pointer - count_delete - count_insert - 1].text
                                    ~= text_insert[0 .. commonlength];
                            } else {
                                diffs.insert(0, [DiffT!Str(Operation.EQUAL, text_insert[0 .. commonlength])]);
                                pointer++;
                            }
                            text_insert = text_insert[commonlength .. $];
                            text_delete = text_delete[commonlength .. $];
                        }
                        // Factor out any common suffixes.
                        if (auto commonlength = commonSuffix(text_insert, text_delete)) {
                            diffs[pointer].text = text_insert[$ - commonlength .. $] ~ diffs[pointer].text;
                            text_insert = text_insert[0 .. $ - commonlength];
                            text_delete = text_delete[0 .. $ - commonlength];
                        }
                    }
                    // Delete the offending records and add the merged ones.
                    if (count_delete == 0) {
                        diffs.splice(
                                pointer - count_insert,
                                count_delete + count_insert,
                                [DiffT!Str(Operation.INSERT, text_insert)]);
                    } else if (count_insert == 0) {
                        diffs.splice(
                                pointer - count_delete,
                                count_delete + count_insert,
                                [DiffT!Str(Operation.DELETE, text_delete)]);
                    } else {
                        diffs.splice(
                                pointer - count_delete - count_insert,
                                count_delete + count_insert,
                                [DiffT!Str(Operation.DELETE, text_delete), DiffT!Str(Operation.INSERT, text_insert)]);
                    }
                    pointer = pointer - count_delete - count_insert +
                            (count_delete != 0 ? 1 : 0) + (count_insert != 0 ? 1 : 0) + 1;
                } else if( pointer != 0 && diffs[pointer-1].operation == Operation.EQUAL ){
                    diffs[pointer - 1].text ~= diffs[pointer].text;
                    diffs.remove(pointer);
                } else {
                    pointer++;
                }
                count_insert = 0;
                count_delete = 0;
                text_delete = "";
                text_insert = "";
                break;
        }
    }
    if( diffs[$-1].text.length == 0){
        diffs.length--;
    }

    bool changes = false;
    pointer = 1;
    while( pointer + 1 < diffs.length ) {
        if( diffs[pointer - 1].operation == Operation.EQUAL &&
            diffs[pointer + 1].operation == Operation.EQUAL)
        {
            if( diffs[pointer].text.endsWith(diffs[pointer - 1].text)) {
                diffs[pointer].text = diffs[pointer - 1].text ~ diffs[pointer].text[0 .. $ - diffs[pointer - 1].text.length];
                diffs[pointer + 1].text = diffs[pointer - 1].text ~ diffs[pointer + 1].text;
                diffs.splice(pointer - 1, 1);
                changes = true;
            } else if( diffs[pointer].text.startsWith(diffs[pointer + 1].text)) {
                diffs[pointer - 1].text ~= diffs[pointer + 1].text;
                diffs[pointer].text =
                    diffs[pointer].text[diffs[pointer + 1].text.length .. $]
                    ~ diffs[pointer + 1].text;
                diffs.splice(pointer + 1, 1);
                changes = true;
            }
        }
        pointer++;
    }
    if( changes ) cleanupMerge(diffs);

}



/**
 * Given two strings, comAdde a score representing whether the internal
 * boundary falls on logical boundaries.
 * Scores range from 6 (best) to 0 (worst).
 * @param one First string.
 * @param two Second string.
 * @return The score.
 */
int cleanupSemanticScore(Str)(Str one, Str two)
{
    if( one.length == 0 || two.length == 0) return 6; //Edges are the best
    auto char1 = one[$-1];
    auto char2 = two[0];

    auto nonAlphaNumeric1 = !(isAlpha(char1) || isNumber(char1));
    auto nonAlphaNumeric2 = !(isAlpha(char2) || isNumber(char2));
    auto whitespace1 = nonAlphaNumeric1 && isWhite(char1);
    auto whitespace2 = nonAlphaNumeric2 && isWhite(char2);
    auto lineBreak1 = whitespace1 && isControl(char1);
    auto lineBreak2 = whitespace2 && isControl(char2);
    auto blankLine1 = lineBreak1 &&  match(one, `\n\r?\n\Z`.to!Str);
    auto blankLine2 = lineBreak2 &&  match(two, `\A\r?\n\r?\n`.to!Str);

    if (blankLine1 || blankLine2) return 5;
    else if (lineBreak1 || lineBreak2) return 4;
    else if (nonAlphaNumeric1 && !whitespace1 && whitespace2) return 3;
    else if (whitespace1 || whitespace2) return 2;
    else if (nonAlphaNumeric1 || nonAlphaNumeric2) return 1;

    return 0;
}


/**
 * Reduce the number of edits by eliminating operationally trivial
 * equalities.
 * @param diffs List of DiffT objects.
 */
void cleanupEfficiency(Str)(ref DiffT!(Str)[] diffs) {
    bool changes = false;
    size_t[] equalities;
    Str lastequality;
    size_t pointer = 0;
    auto pre_ins = false;
    auto pre_del = false;
    auto post_ins = false;
    auto post_del = false;
    while( pointer < diffs.length ){
        if( diffs[pointer].operation == Operation.EQUAL ){
            if( diffs[pointer].text.length < DIFF_EDIT_COST && (post_ins || post_del)) {
                equalities ~= pointer;
                pre_ins = post_ins;
                pre_del = post_del;
                lastequality = diffs[pointer].text;
            } else {
                equalities.length = 0;
                equalities.assumeSafeAppend;
                lastequality = "";
            }
            post_ins = false;
            post_del = false;
        } else {
            if( diffs[pointer].operation == Operation.DELETE ){
                post_del = true;
            } else {
                post_ins = true;
            }

            if( lastequality.length != 0
                && (
                    (pre_ins && pre_del && post_ins && post_del)
                    || ((lastequality.length < DIFF_EDIT_COST / 2)
                        && ((pre_ins ? 1 : 0) + (pre_del ? 1 : 0) + (post_ins ? 1 : 0) + (post_del ? 1 : 0)) == 3)
                    )
                )
            {
                diffs.insert(equalities[$-1], [DiffT!Str(Operation.DELETE, lastequality)]);
                diffs[equalities[$-1] + 1].operation = Operation.INSERT;
                equalities.length--;
                equalities.assumeSafeAppend;
                lastequality = "";
                if( pre_ins && pre_del ){
                    post_ins = true;
                    post_del = true;
                    equalities.length = 0;
                    equalities.assumeSafeAppend;
                } else {
                    if( equalities.length > 0 ) {
                        equalities.length--;
                        equalities.assumeSafeAppend;
                    }

                    pointer = equalities.length > 0 ? equalities[$-1] : -1;
                    post_ins = false;
                    post_del = false;
                }
                changes = true;
            }
        }
        pointer++;
    }

    if( changes ){
        cleanupMerge(diffs);
    }
}

/**
 * loc is a location in text1, comAdde and return the equivalent location in
 * text2.
 * e.g. "The cat" vs "The big cat", 1->1, 5->8
 * @param diffs List of DiffT objects.
 * @param loc Location within text1.
 * @return Location within text2.
 */
sizediff_t xIndex(Str)(DiffT!(Str)[] diffs, sizediff_t loc) {
    auto chars1 = 0;
    auto chars2 = 0;
    auto last_chars1 = 0;
    auto last_chars2 = 0;
    DiffT!Str lastDiffT;
    foreach ( diff; diffs) {
        if (diff.operation != Operation.INSERT) {
            // Equality or deletion.
            chars1 += diff.text.length;
        }
        if (diff.operation != Operation.DELETE) {
            // Equality or insertion.
            chars2 += diff.text.length;
        }
        if (chars1 > loc) {
            // Overshot the location.
            lastDiffT = diff;
            break;
        }
        last_chars1 = chars1;
        last_chars2 = chars2;
    }
    if (lastDiffT.operation == Operation.DELETE) {
        // The location was deleted.
        return last_chars2;
    }
    // Add the remaining character length.
    return last_chars2 + (loc - last_chars1);
}

/**
 * Unescape selected chars for compatability with JavaScript's encodeURI.
 * In speed critical applications this could be dropped since the
 * receiving application will certainly decode these fine.
 * Note that this function is case-sensitive.  Thus "%3F" would not be
 * unescaped.  But this is ok because it is only called with the output of
 * HttpUtility.UrlEncode which returns lowercase hex.
 *
 * Example: "%3f" -> "?", "%24" -> "$", etc.
 *
 * @param str The string to escape.
 * @return The escaped string.
 */
public static string unescapeForEncodeUriCompatibility(string str)
{
    // FIXME: this is ridiculously inefficient
    return str.replace("%21", "!").replace("%7e", "~")
      .replace("%27", "'").replace("%28", "(").replace("%29", ")")
      .replace("%3b", ";").replace("%2f", "/").replace("%3f", "?")
      .replace("%3a", ":").replace("%40", "@").replace("%26", "&")
      .replace("%3d", "=").replace("%2b", "+").replace("%24", "$")
      .replace("%2c", ",").replace("%23", "#");
}
