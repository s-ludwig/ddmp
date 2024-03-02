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
module ddmp.patch;
import std.algorithm : min, max;
import std.array;
import std.conv;
import std.exception : enforce;
import std.range : ElementEncodingType;
import std.string:lastIndexOf;
import std.utf : toUTF16, toUTF8;
import std.traits : isSomeString, Unqual;

import ddmp.diff;
import ddmp.match;
import ddmp.util;

int MATCH_MAXBITS = 32;
int PATCH_MARGIN = 4;
float PATCH_DELETE_THRESHOLD = 0.5f;

alias Patch = PatchT!string;

struct PatchT(Str) {
    DiffT!(Str)[] diffs;
    sizediff_t start1;
    sizediff_t start2;
    sizediff_t length1;
    sizediff_t length2;

    bool isNull() const {
        if (start1 == 0 && start2 == 0 && length1 == 0 && length2 == 0
                && diffs.length == 0) {
            return true;
        }
        return false;
    }

    string toString()
    const {
    	import std.uri : encode;

        auto app = appender!string();
        app.put("@@ -");
        if( length1 == 0 ){
            app.put(to!string(start1));
            app.put(",0");
        } else if( length1 == 1 ){
            app.put(to!string(start1 + 1));
        } else {
            app.put(to!string(start1 + 1));
            app.put(",");
            app.put(to!string(length1));
        }
        app.put(" +");
        if( length2 == 0 ){
            app.put(to!string(start2));
            app.put(",0");
        } else if( length2 == 1 ){
            app.put(to!string(start2 + 1));
        } else {
            app.put(to!string(start2 + 1));
            app.put(",");
            app.put(to!string(length2));
        }
        app.put(" @@\n");
        foreach( d ; diffs){
            final switch( d.operation ){
                case Operation.INSERT:
                    app.put("+");
                    break;
                case Operation.DELETE:
                    app.put("-");
                    break;
                case Operation.EQUAL:
                    app.put(" ");
                    break;
            }
            app.put(encode(d.text).replace("%20", " "));
            app.put("\n");
        }

        return unescapeForEncodeUriCompatibility(app.data());
    }
}

/**
 * Increase the context until it is unique,
 * but don't let the pattern expand beyond Match_MaxBits.
 * @param patch The patch to grow.
 * @param text Source text.
 */
void addContext(Str)(ref PatchT!Str patch, Str text)
{
	if( text.length == 0 ) return;

	auto pattern = text.substr(patch.start2, patch.length1);
	sizediff_t padding = 0;

	// Look for the first and last matches of pattern in text.  If two
	// different matches are found, increase the pattern length.
	while( text.indexOfAlt(pattern) != text.lastIndexOf(pattern)
            && pattern.length < MATCH_MAXBITS - PATCH_MARGIN - PATCH_MARGIN ){
		padding += PATCH_MARGIN;
		pattern = text.substr(
                max(0, patch.start2 - padding),
                min(text.length, patch.start2 + patch.length1 + padding) - max(0, patch.start2 - padding));
	}
	// Add one chunk for good luck.
	padding += PATCH_MARGIN;

	// Add the prefix.
	auto prefix = text.substr(
            max(0, patch.start2 - padding),
            patch.start2 - max(0, patch.start2 - padding));
	if( prefix.length != 0 ){
		patch.diffs.insert(0, [DiffT!Str(Operation.EQUAL, prefix)]);
	}

	// Add the suffix.
	auto suffix = text.substr(
            patch.start2 + patch.length1,
            min(text.length, patch.start2 + patch.length1 + padding) - (patch.start2 + patch.length1));
	if( suffix.length != 0 ){
		patch.diffs ~= DiffT!Str(Operation.EQUAL, suffix);
	}

	// Roll back the start points.
	patch.start1 -= prefix.length;
	patch.start2 -= prefix.length;
	// Extend the lengths.
	patch.length1 += prefix.length + suffix.length;
	patch.length2 += prefix.length + suffix.length;
}

/**
* Compute a list of patches to turn text1 into text2.
* A set of diffs will be computed.
* @param text1 Old text.
* @param text2 New text.
* @return List of PatchT objects.
*/
PatchT!(Str)[] patch_make(Str)(Str text1, Str text2) {
	// No diffs provided, comAdde our own.
	auto diffs = diff_main(text1, text2, true);
	if (diffs.length > 2) {
		cleanupSemantic(diffs);
		cleanupEfficiency(diffs);
	}
	return patch_make(text1, diffs);
}


/**
 * Compute a list of patches to turn text1 into text2.
 * text1 will be derived from the provided diffs.
 * @param diffs Array of DiffT objects for text1 to text2.
 * @return List of PatchT objects.
 */
PatchT!(Str)[] patch_make(Str)(DiffT!(Str)[] diffs)
if (isSomeString!Str) {
    // Check for null inputs not needed since null can't be passed in C#.
    // No origin string provided, comAdde our own.
    auto text1 = diff_text1(diffs);
    return patch_make(text1, diffs);
}


/**
 * Compute a list of patches to turn text1 into text2.
 * text2 is not provided, diffs are the delta between text1 and text2.
 * @param text1 Old text.
 * @param diffs Array of DiffT objects for text1 to text2.
 * @return List of PatchT objects.
 */
PatchT!(Str)[] patch_make(Str)(Str text1, DiffT!(Str)[] diffs)
{
	PatchT!(Str)[] patches;
	if( diffs.length == 0 ) return patches;

	PatchT!Str patch;
	auto char_count1 = 0;  // Number of characters into the text1 string.
	auto char_count2 = 0;  // Number of characters into the text2 string.
	// Start with text1 (prepatch_text) and apply the diffs until we arrive at
	// text2 (postpatch_text). We recreate the patches one by one to determine
	// context info.
	auto prepatch_text = text1;
	auto postpatch_text = text1;

	foreach( diff ; diffs ){
		if( patch.diffs.length == 0 && diff.operation != Operation.EQUAL ){
			// A new patch starts here.
			patch.start1 = char_count1;
			patch.start2 = char_count2;
		}

		final switch(diff.operation){
			case Operation.INSERT:
				patch.diffs ~= diff;
				patch.length2 += diff.text.length;
				postpatch_text.insert(char_count2, diff.text);
				break;
			case Operation.DELETE:
				patch.length1 += diff.text.length;
				patch.diffs ~= diff;
				postpatch_text.remove(char_count2, diff.text.length);
				break;
			case Operation.EQUAL:
				if( diff.text.length <= 2 * PATCH_MARGIN && patch.diffs.length != 0 && diff != diffs[$-1] ){
					patch.diffs ~= diff;
					patch.length1 += diff.text.length;
					patch.length2 += diff.text.length;
				}

				if( diff.text.length >= 2 * PATCH_MARGIN ){
					if( patch.diffs.length != 0 ){
						addContext(patch, prepatch_text);
						patches ~= patch;
						patch = PatchT!Str();
						prepatch_text = postpatch_text;
						char_count1 = char_count2;
					}
				}
				break;
		}
        // Update the current character count.
        if (diff.operation != Operation.INSERT) {
            char_count1 += diff.text.length;
        }
        if (diff.operation != Operation.DELETE) {
            char_count2 += diff.text.length;
        }
    }
	// Pick up the leftover patch if not empty.
    if( !patch.diffs.empty ){
    	addContext(patch, prepatch_text);
    	patches ~= patch;
    }

    return patches;
}


alias PatchApplyResult = PatchApplyResultT!string;

/**
 * Merge a set of patches onto the text.  Return a patched text, as well
 * as an array of true/false values indicating which patches were applied.
 * @param patches Array of PatchT objects
 * @param text Old text.
 * @return Two element Object array, containing the new text and an array of
 *      bool values.
 */

struct PatchApplyResultT(Str) {
 	Str text;
 	bool[] patchesApplied;
}

PatchApplyResultT!Str apply(Str)(PatchT!(Str)[] patches, Str text)
{
    PatchApplyResultT!Str result = PatchApplyResultT!Str(text, []);
    if( patches.length == 0 ) return result;

    // Deep copy the patches so that no changes are made to the originals.
    PatchT!(Str)[] patchesCopy = patches.dup;

    auto nullPadding = addPadding(patchesCopy);
 	text = nullPadding ~ text ~ nullPadding;
 	splitMax(patchesCopy);

 	sizediff_t x = 0;
	// delta keeps track of the offset between the expected and actual
	// location of the previous patch.  If there are patches expected at
	// positions 10 and 20, but the first patch was found at 12, delta is 2
	// and the second patch has an effective expected position of 22.
	sizediff_t delta = 0;
 	result.patchesApplied.length = patchesCopy.length; // init patchesApplied array
	foreach( patch ; patchesCopy ){
		auto expected_loc = patch.start2 + delta;
		auto text1 =  diff_text1(patch.diffs);
		sizediff_t start_loc;
		sizediff_t end_loc = -1;
		if( text1.length > MATCH_MAXBITS ){
			// patch_splitMax will only provide an oversized pattern
         	// in the case of a monster delete
         	start_loc = match_main(text, text1.substr(0, MATCH_MAXBITS), expected_loc);
         	if( start_loc != -1 ){
         		end_loc = match_main(text,
         			text1[$ - MATCH_MAXBITS .. $],
         			expected_loc + text1.length - MATCH_MAXBITS);
         		if( end_loc == -1 || start_loc >= end_loc ){
         			// Can't find valid trailing context.  Drop this patch.
         			start_loc = -1;
         		}
         	}
		} else {
			start_loc = match_main(text, text1, expected_loc);
		}
		if( start_loc == -1 ){
			// No match found.  :(
			result.patchesApplied[x] = false;
			// Subtract the delta for this failed patch from subsequent patches.
			delta -= patch.length2 - patch.length1;
		} else {
			// Found a match. :)
			result.patchesApplied[x] = true;
			delta = start_loc - expected_loc;
			Str text2;
			if( end_loc == -1 ){
				text2 = text[ start_loc .. min(start_loc + text1.length, text.length) ];
			} else {
				text2 = text[ start_loc .. min(end_loc + MATCH_MAXBITS - start_loc, text.length) ];
			}
			if( text1 == text2 ) {
				// Perfect match, just shove the replacement text in.
				text = text.substr(0, start_loc) ~ diff_text2(patch.diffs) ~ text.substr(start_loc + text1.length);
			} else {
				// Imperfect match. Run a diff to get a framework of equivalent indices.
				auto diffs = diff_main(text1, text2, false);
				if( text1.length > MATCH_MAXBITS && levenshtein(diffs) / cast(float)text1.length > PATCH_DELETE_THRESHOLD){
					// The end points match, but the content is unacceptably bad.
					result.patchesApplied[x] = false;
				} else {
					cleanupSemanticLossless(diffs);
					auto index1 = 0;
					foreach( diff; patch.diffs ){
						if( diff.operation != Operation.EQUAL ){
							auto index2 = xIndex(diffs, index1);
							if( diff.operation == Operation.INSERT ){
								// Insertion
								text.insert(start_loc + index2, diff.text);
							} else if( diff.operation == Operation.DELETE ){
								// Deletion
								//text.remove(start_loc + index2, xIndex(diffs, index1 + diff.text.length) - index2);
                                text = text[0 .. start_loc + index2]
                                        ~ text[min(text.length, start_loc
                                            + xIndex(diffs, index1 + diff.text.length)) .. $];
							}
						}
						if( diff.operation != Operation.DELETE ){
							index1 += diff.text.length;
						}
					}
				}
			}
		}
		x++;
	}
	// Strip the padding off.
	result.text = text.substr(nullPadding.length, text.length - 2 * nullPadding.length);
	return result;
}

/**
 * Add some padding on text start and end so that edges can match something.
 * Intended to be called only from within patch_apply.
 * @param patches Array of PatchT objects.
 * @return The padding string added to each side.
 */
Str addPadding(Str)(ref PatchT!(Str)[] patches)
{
	auto paddingLength = PATCH_MARGIN;
	Str nullPadding;
	for(sizediff_t x = 1; x <= paddingLength; x++){
		nullPadding ~= cast(char)x;
	}

	// Bump all the patches forward.
	foreach( ref patch; patches ){
		patch.start1 += paddingLength;
		patch.start2 += paddingLength;
	}

	// Add some padding on start of first diff.
	PatchT!(Str)* firstPatch = &(patches[0]);
	auto firstPatchDiffs = &(firstPatch.diffs);
	if( firstPatchDiffs.length == 0 || (*firstPatchDiffs)[0].operation != Operation.EQUAL ){
		// Add nullPadding equality.
		(*firstPatchDiffs).insert(0, [DiffT!Str(Operation.EQUAL, nullPadding)]);
		firstPatch.start1 -= paddingLength;  // Should be 0.
		firstPatch.start2 -= paddingLength;  // Should be 0.
		firstPatch.length1 += paddingLength;
		firstPatch.length2 += paddingLength;
	} else if (paddingLength > (*firstPatchDiffs)[0].text.length) {
		// Grow first equality.
		DiffT!(Str)* firstDiff = &((*firstPatchDiffs)[0]);
		auto extraLength = paddingLength - firstDiff.text.length;
		firstDiff.text = nullPadding.substr(firstDiff.text.length) ~ firstDiff.text;
		firstPatch.start1 -= extraLength;
		firstPatch.start2 -= extraLength;
		firstPatch.length1 += extraLength;
		firstPatch.length2 += extraLength;
	}

	// Add some padding on end of last diff.
	PatchT!(Str)* lastPatch = &(patches[0]);
	auto lastPatchDiffs = &(lastPatch.diffs);
	if( lastPatchDiffs.length == 0 || (*lastPatchDiffs)[$-1].operation != Operation.EQUAL) {
		// Add nullPadding equality.
		(*lastPatchDiffs) ~= DiffT!Str(Operation.EQUAL, nullPadding);
		lastPatch.length1 += paddingLength;
		lastPatch.length2 += paddingLength;
	} else if (paddingLength > (*lastPatchDiffs)[$-1].text.length) {
		// Grow last equality.
		DiffT!(Str)* lastDiff = &((*lastPatchDiffs)[$-1]);
		auto extraLength = paddingLength - lastDiff.text.length;
		lastDiff.text ~= nullPadding.substr(0, extraLength);
		lastPatch.length1 += extraLength;
		lastPatch.length2 += extraLength;
	}
	return nullPadding;
}

/**
 * Look through the patches and break up any which are longer than the
 * maximum limit of the match algorithm.
 * Intended to be called only from within patch_apply.
 * @param patches List of PatchT objects.
 */
void splitMax(Str)(ref PatchT!(Str)[] patches)
{
	auto patch_size = MATCH_MAXBITS;
    int x = 0;  // The index of the next patch to check.
    PatchT!Str bigpatch = x < patches.length ? patches[x++] : PatchT!Str();
	while (!bigpatch.isNull()) {
		if( bigpatch.length1 <= patch_size ) {
            bigpatch = x < patches.length ? patches[x++] : PatchT!Str();
            continue;
        }
        // Remove the big old patch.
		patches.splice(--x, 1);
		auto start1 = bigpatch.start1;
		auto start2 = bigpatch.start2;
		Str precontext;
		while( bigpatch.diffs.length != 0){
			PatchT!Str patch;
			bool empty = true;
			patch.start1 = start1 - precontext.length;
			patch.start2 = start2 - precontext.length;
			if( precontext.length != 0 ){
				patch.length1 = patch.length2 = precontext.length;
				patch.diffs ~= DiffT!Str(Operation.EQUAL, precontext);
			}
			while( bigpatch.diffs.length != 0
                    && patch.length1 < patch_size - PATCH_MARGIN ){
				Operation diff_type = bigpatch.diffs[0].operation;
				auto diff_text = bigpatch.diffs[0].text;
				if( diff_type == Operation.INSERT ){
					// Insertions are harmless.
					patch.length2 += diff_text.length;
					start2 += diff_text.length;
					patch.diffs ~= bigpatch.diffs[0];
					bigpatch.diffs.remove(0);
					empty = false;
				} else if( diff_type == Operation.DELETE && patch.diffs.length == 1
					&& patch.diffs[0].operation == Operation.EQUAL
					&& diff_text.length > 2 * patch_size) {
              		// This is a large deletion.  Let it pass in one chunk.
              		patch.length1 += diff_text.length;
              		start1 += diff_text.length;
              		empty = false;
              		patch.diffs ~= DiffT!Str(diff_type, diff_text);
              		bigpatch.diffs.remove(0);
				} else {
					// Deletion or equality. Only takes as much as we can stomach.
					diff_text = diff_text.substr(0, min(diff_text.length,
                            patch_size - patch.length1 - PATCH_MARGIN));
					patch.length1 += diff_text.length;
					start1 += diff_text.length;
					if( diff_type == Operation.EQUAL ){
						patch.length2 += diff_text.length;
						start2 += diff_text.length;
					} else {
						empty = false;
					}
					patch.diffs ~= DiffT!Str(diff_type, diff_text);
					if( diff_text == bigpatch.diffs[0].text ){
						bigpatch.diffs.remove(0);
					} else {
						bigpatch.diffs[0].text = bigpatch.diffs[0].text.substr(diff_text.length);
					}
				}
			}
			// Compute the head context for the next patch.
			precontext = diff_text2(patch.diffs);
			precontext = precontext.substr(max(0, precontext.length - PATCH_MARGIN));

			auto postcontext = diff_text1(bigpatch.diffs);
			if( diff_text1(bigpatch.diffs).length > PATCH_MARGIN ){
				postcontext =  postcontext.substr(0, PATCH_MARGIN);
			}

			if( postcontext.length != 0 ){
				patch.length1 += postcontext.length;
				patch.length2 += postcontext.length;
				if( patch.diffs.length != 0
                        && patch.diffs[$-1].operation == Operation.EQUAL) {
					patch.diffs[$-1].text ~= postcontext;
				} else {
					patch.diffs ~= DiffT!Str(Operation.EQUAL, postcontext);
				}
			}
			if( !empty ){
				patches.splice(x++, 0, [patch]);
			}
		}
        bigpatch = x < patches.length ? patches[x++] : PatchT!Str();
	}
}

/**
 * Take a list of patches and return a textual representation.
 * @param patches List of PatchT objects.
 * @return Text representation of patches.
 */
public string patch_toText(Str)(in PatchT!(Str)[] patches)
{
	auto text = appender!Str();
	foreach (aPatchT; patches)
		text ~= aPatchT.toString();
	return text.data;
}

/**
 * Parse a textual representation of patches and return a List of PatchT
 * objects.
 * @param textline Text representation of patches.
 * @return List of PatchT objects.
 * @throws ArgumentException If invalid input.
 */
public PatchT!(Str)[] patch_fromText(Str)(Str textline)
{
	import std.regex : regex, matchFirst;
	import std.string : format, split;

	auto patches = appender!(PatchT!(Str)[])();
	if (textline.length == 0) return null;

	auto text = textline.split("\n");
	sizediff_t textPointer = 0;
	auto patchHeader = regex("^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@$");
	Unqual!(ElementEncodingType!Str) sign;
	Str line;
	while (textPointer < text.length) {
		auto m = matchFirst(text[textPointer], patchHeader);
		enforce (m, "Invalid patch string: " ~ text[textPointer]);
		PatchT!Str patch;
		patch.start1 = m[1].to!sizediff_t;
		if (m[2].length == 0) {
			patch.start1--;
			patch.length1 = 1;
		} else if (m[2] == "0") {
			patch.length1 = 0;
		} else {
			patch.start1--;
			patch.length1 = m[2].to!sizediff_t;
		}

		patch.start2 = m[3].to!sizediff_t;
		if (m[4].length == 0) {
			patch.start2--;
			patch.length2 = 1;
		} else if (m[4] == "0") {
			patch.length2 = 0;
		} else {
			patch.start2--;
			patch.length2 = m[4].to!sizediff_t;
		}
		textPointer++;

		while (textPointer < text.length) {
			import std.uri : decodeComponent;
			if (textPointer >= text.length || !text[textPointer].length) {
				// Blank line?  Whatever.
				textPointer++;
				continue;
			}
			sign = text[textPointer][0];
			line = text[textPointer][1 .. $];
			line = line.replace("+", "%2b");
			line = decodeComponent(line);
			if (sign == '-') {
				// Deletion.
				patch.diffs ~= DiffT!Str(Operation.DELETE, line);
			} else if (sign == '+') {
				// Insertion.
				patch.diffs ~= DiffT!Str(Operation.INSERT, line);
			} else if (sign == ' ') {
				// Minor equality.
				patch.diffs ~= DiffT!Str(Operation.EQUAL, line);
			} else if (sign == '@') {
				// Start of next patch.
				break;
			} else {
				// WTF?
				throw new Exception(format("Invalid patch mode '%s' in: %s", sign, line));
			}
			textPointer++;
		}

		patches ~= patch;
	}
	return patches.data;
}
