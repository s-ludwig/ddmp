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
module ddmp.match;

import std.algorithm : min, max;
import std.array;
import std.math : abs;
import std.range : ElementEncodingType;
import std.string;
import std.utf : toUTF16, toUTF8;
import std.traits : isSomeString, Unqual;
import std.exception : enforce;

import ddmp.util;

float MATCH_THRESHOLD = 0.5f;
int MATCH_DISTANCE = 1000;

/**
 * Locate the best instance of 'pattern' in 'text' near 'loc'.
 * Returns -1 if no match found.
 * @param text The text to search.
 * @param pattern The pattern to search for.
 * @param loc The location to search around.
 * @return Best match index or -1.
 */
sizediff_t match_main(Str)(Str text, Str pattern, sizediff_t loc)
if (isSomeString!Str) {
	loc = max(0, min(loc, text.length));
	if( text == pattern ){
		return 0; // Shortcut (potentially not guaranteed by the algorithm)
	} else if( text.length == 0 ){
		return -1; // Nothing to match
	} else if( loc + pattern.length <= text.length && text.substr(loc, pattern.length) == pattern){
		return loc; // Perfect match at the perfect spot! (Includes case of null pattern)
	} else {
		return bitap(text, pattern, loc);
	}
}


/**
 * Locate the best instance of 'pattern' in 'text' near 'loc' using the
 * Bitap algorithm.  Returns -1 if no match found.
 * @param text The text to search.
 * @param pattern The pattern to search for.
 * @param loc The location to search around.
 * @return Best match index or -1.
 */
sizediff_t bitap(Str)(Str text, Str pattern, sizediff_t loc)
if (isSomeString!Str) {
	// bits need to fit into the positive part of an int
	enforce(pattern.length <= 32, "Pattern too long for this application.");

	int[Unqual!(ElementEncodingType!Str)] s = initAlphabet(pattern);
	double score_threshold = MATCH_THRESHOLD;
	auto best_loc = text.indexOfAlt(pattern, loc);
	if( best_loc != -1 ){
		score_threshold = min(bitapScore(0, best_loc, loc, pattern), score_threshold);

		best_loc = text[0..min(loc + pattern.length, text.length)].lastIndexOf(pattern);
		if( best_loc != -1){
			score_threshold = min(bitapScore(0, best_loc, loc, pattern), score_threshold);
		}
	}

	sizediff_t matchmask = 1 << (pattern.length - 1);
	best_loc = -1;

	sizediff_t bin_min;
	sizediff_t bin_mid;
	sizediff_t bin_max = pattern.length + text.length;

	sizediff_t[] last_rd;
    for(sizediff_t d = 0; d < pattern.length; d++){
        // Scan for the best match; each iteration allows for one more error.
        // Run a binary search to determine how far from 'loc' we can stray at
        // this error level.
        bin_min = 0;
        bin_mid = bin_max;
        while( bin_min < bin_mid ){
        	if( bitapScore(d, loc + bin_mid, loc, pattern) <= score_threshold){
        		bin_min = bin_mid;
        	} else {
        		bin_max = bin_mid;
        	}
        	bin_mid = (bin_max - bin_min) / 2 + bin_min;
        }
        bin_max = bin_mid;
        sizediff_t start = max(1, loc - bin_mid + 1);
        sizediff_t finish = min(loc + bin_mid, text.length) + pattern.length;

		sizediff_t[] rd = new sizediff_t[finish + 2];
		rd[finish + 1] = (1 << d) - 1;
		for( sizediff_t j = finish; j >= start; j--) {
			sizediff_t charMatch;
			if( text.length <= j - 1 || !( text[j - 1] in s) ) {
				charMatch = 0;
			} else {
				charMatch = s[text[j - 1]];
			}
			if( d == 0 ){
				rd[j] = ((rd[j + 1] << 1) | 1) & charMatch;
			} else {
				rd[j] = ((rd[j + 1] << 1) | 1) & charMatch | (((last_rd[j + 1] | last_rd[j]) << 1) | 1) | last_rd[j + 1];
			}
			if( (rd[j] & matchmask) != 0) {
				auto score = bitapScore(d, j - 1, loc, pattern);
				if( score <= score_threshold ){
					score_threshold = score;
					best_loc = j - 1;
					if( best_loc > loc ){
						start = max(1, 2 * loc - best_loc);
					} else {
						break;
					}
				}
			}
		}
		if( bitapScore(d + 1, loc, loc, pattern) > score_threshold) {
			break;
		}
		last_rd = rd;
    }
    return best_loc;
}

/**
 * Compute and return the score for a match with e errors and x location.
 * @param e Number of errors in match.
 * @param x Location of match.
 * @param loc Expected location of match.
 * @param pattern Pattern being sought.
 * @return Overall score for match (0.0 = good, 1.0 = bad).
 */
double bitapScore(Str)(sizediff_t e, sizediff_t x, sizediff_t loc, Str pattern)
if (isSomeString!Str) {
	auto accuracy = cast(float)e / pattern.length;
	sizediff_t proximity = abs(loc - x);
	if( MATCH_DISTANCE == 0 ){
		return proximity == 0 ? accuracy : 1.0;
	}
	return accuracy + (proximity / cast(float)MATCH_DISTANCE);
}

/**
 * Initialise the alphabet for the Bitap algorithm.
 * @param pattern The text to encode.
 * @return Hash of character locations.
 */
int[Unqual!(ElementEncodingType!Str)] initAlphabet(Str)(Str pattern)
if (isSomeString!Str) {
	int[Unqual!(ElementEncodingType!Str)] s;
	foreach( c ; pattern ){
		if( c !in s )s[c] = 0;
	}
	foreach( i, c; pattern ){
		auto value = s[c] | (1 << (pattern.length - i - 1));
		s[c] = value;
	}
	return s;
}
