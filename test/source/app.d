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
module app;

import ddmp.diff;
import ddmp.patch;
import ddmp.match;

import core.time;
import std.datetime;
import std.exception;
import std.stdio;

void testDiffCommonPrefix() {
  // Detect any common prefix.
  // Null case.
  assert(0 == commonPrefix("abc", "xyz"));

  // Non-null case.
  assert(4 == commonPrefix("1234abcdef", "1234xyz"));

  // Whole case.
  assert(4 == commonPrefix("1234", "1234xyz"));
}

void testDiffCommonSuffix() {
  // Detect any common suffix.
  // Null case.
  assert(0 == commonSuffix("abc", "xyz"));

  // Non-null case.
  assert(4 == commonSuffix("abcdef1234", "xyz1234"));

  // Whole case.
  assert(4 == commonSuffix("1234", "xyz1234"));
}

void testDiffCommonOverlap() {
  // Detect any suffix/prefix overlap.
  // Null case.
  assert(0 == commonOverlap("", "abcd"));

  // Whole case.
  assert(3 == commonOverlap("abc", "abcd"));

  // No overlap.
  assert(0 == commonOverlap("123456", "abcd"));

  // Overlap.
  assert(3 == commonOverlap("123456xxx", "xxxabcd"));

  // Unicode.
  // Some overly clever languages (C#) may treat ligatures as equal to their
  // component letters.  E.g. U+FB01 == "fi"
  assert(0 == commonOverlap("fi", "\ufb01i"));
}

void testDiffHalfMatch() {
  // No match.
	{
		HalfMatch hm_cmp, hm;
		assert(!halfMatch("1234567890", "abcdef", hm_cmp));
	}

	{
		HalfMatch hm_cmp, hm;
		assert(!halfMatch("12345", "23", hm_cmp));
	}
  // Single Match.
	{
		HalfMatch hm_cmp, hm;
		hm.prefix1 = "12"; hm.suffix1 = "90"; hm.prefix2 ="a"; hm.suffix2 = "z"; hm.commonMiddle = "345678";
		halfMatch("1234567890", "a345678z", hm_cmp);
		assert(hm == hm_cmp);
	}
  {
    HalfMatch hm_cmp, hm;
    hm.prefix1 = "a"; hm.suffix1 = "z"; hm.prefix2 ="12"; hm.suffix2 = "90"; hm.commonMiddle = "345678";
    halfMatch("a345678z", "1234567890", hm_cmp);
    assert(hm == hm_cmp);
  }
	{
		HalfMatch hm_cmp, hm;
		hm.prefix1 = "abc"; hm.suffix1 = "z"; hm.prefix2 ="1234"; hm.suffix2 = "0"; hm.commonMiddle = "56789";
		assert(halfMatch("abc56789z", "1234567890", hm_cmp));
		assert(hm == hm_cmp);
	}

	{
		HalfMatch hm_cmp, hm;
		hm.prefix1 = "a"; hm.suffix1 = "xyz"; hm.prefix2 ="1"; hm.suffix2 = "7890"; hm.commonMiddle = "23456";
		assert(halfMatch("a23456xyz", "1234567890", hm_cmp));
		assert(hm == hm_cmp);
	}

  // Multiple Matches.
  {
    HalfMatch hm_cmp, hm;
    hm.prefix1 = "12123"; hm.suffix1 = "123121"; hm.prefix2 ="a"; hm.suffix2 = "z"; hm.commonMiddle = "1234123451234";
    assert(halfMatch("121231234123451234123121", "a1234123451234z", hm_cmp));
    assert(hm == hm_cmp);
  }

  {
    HalfMatch hm_cmp, hm;
    hm.prefix1 = ""; hm.suffix1 = "-=-=-=-=-="; hm.prefix2 ="x"; hm.suffix2 = ""; hm.commonMiddle = "x-=-=-=-=-=-=-=";
    assert(halfMatch("x-=-=-=-=-=-=-=-=-=-=-=-=", "xx-=-=-=-=-=-=-=", hm_cmp));
    assert(hm == hm_cmp);
  }

  {
    HalfMatch hm_cmp, hm;
    hm.prefix1 = "-=-=-=-=-="; hm.suffix1 = ""; hm.prefix2 = ""; hm.suffix2 = "y"; hm.commonMiddle = "-=-=-=-=-=-=-=y";
    assert(halfMatch("-=-=-=-=-=-=-=-=-=-=-=-=y", "-=-=-=-=-=-=-=yy", hm_cmp));
    assert(hm == hm_cmp);
  }
}

void testDiffLinesToChars() {
  {
    LinesToCharsResult result;
    result.text1 = "\x01\x02\x01";
    result.text2 = "\x02\x01\x02";
    result.uniqueStrings = ["", "alpha\n", "beta\n"];
    assert(result == linesToChars("alpha\nbeta\nalpha\n", "beta\nalpha\nbeta\n"));
  }
  {
    LinesToCharsResult result;
    result.text1 = "";
    result.text2 = "\x01\x02\x03\x03";
    result.uniqueStrings = ["", "alpha\r\n", "beta\r\n", "\r\n"];
    assert(result == linesToChars("", "alpha\r\nbeta\r\n\r\n\r\n"));
  }
  {
    LinesToCharsResult result;
    result.text1 = "\x01";
    result.text2 = "\x02";
    result.uniqueStrings = ["", "a", "b"];
    assert(result == linesToChars("a", "b"));
  }
}

void testDiffCleanupMerge() {
  {
    //Null case
    Diff[] diffs = [];
    cleanupMerge(diffs);
    assert([] == diffs);
  }
  {
    // No change case.
    Diff[] diffs = [Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "b"), Diff(Operation.INSERT, "c")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "b"), Diff(Operation.INSERT, "c")] == diffs);
  }

  {
    // Merge equalities.
    Diff[] diffs = [Diff(Operation.EQUAL, "a"), Diff(Operation.EQUAL, "b"), Diff(Operation.EQUAL, "c")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "abc")] == diffs);
  }
  {
    // Merge deletions.
    Diff[] diffs = [Diff(Operation.DELETE, "a"), Diff(Operation.DELETE, "b"), Diff(Operation.DELETE, "c")];
    cleanupMerge(diffs);
    assert([Diff(Operation.DELETE, "abc")] == diffs);
  }
  {
    // Merge insertions.
    Diff[] diffs = [Diff(Operation.INSERT, "a"), Diff(Operation.INSERT, "b"), Diff(Operation.INSERT, "c")];
    cleanupMerge(diffs);
    assert([Diff(Operation.INSERT, "abc")] == diffs);
  }
  {
    // Merge interweave.
    Diff[] diffs = [Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "b"), Diff(Operation.DELETE, "c"), Diff(Operation.INSERT, "d"), Diff(Operation.EQUAL, "e"), Diff(Operation.EQUAL, "f")];
    cleanupMerge(diffs);
    assert([Diff(Operation.DELETE, "ac"), Diff(Operation.INSERT, "bd"), Diff(Operation.EQUAL, "ef")] == diffs);
  }
  {
    // Prefix and suffix detection.
    Diff[] diffs = [Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "abc"), Diff(Operation.DELETE, "dc")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "d"), Diff(Operation.INSERT, "b"), Diff(Operation.EQUAL, "c")] == diffs);
  }
  {
    // Prefix and suffix detection with equalities.
    Diff[] diffs = [Diff(Operation.EQUAL, "x"), Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "abc"), Diff(Operation.DELETE, "dc"), Diff(Operation.EQUAL, "y")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "xa"), Diff(Operation.DELETE, "d"), Diff(Operation.INSERT, "b"), Diff(Operation.EQUAL, "cy")] == diffs);
  }
  {
    // Slide edit left.
    Diff[] diffs = [Diff(Operation.EQUAL, "a"), Diff(Operation.INSERT, "ba"), Diff(Operation.EQUAL, "c")];
    cleanupMerge(diffs);
    assert([Diff(Operation.INSERT, "ab"), Diff(Operation.EQUAL, "ac")] == diffs);
  }
  {
    // Slide edit right.
    Diff[] diffs = [Diff(Operation.EQUAL, "c"), Diff(Operation.INSERT, "ab"), Diff(Operation.EQUAL, "a")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "ca"), Diff(Operation.INSERT, "ba")] == diffs);
  }
    {
    // Slide edit left recursive.
    Diff[] diffs = [Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "b"), Diff(Operation.EQUAL, "c"), Diff(Operation.DELETE, "ac"), Diff(Operation.EQUAL, "x")];
    cleanupMerge(diffs);
    assert([Diff(Operation.DELETE, "abc"), Diff(Operation.EQUAL, "acx")] == diffs);
  }
  {
    // Slide edit right recursive.
    Diff[] diffs = [Diff(Operation.EQUAL, "x"), Diff(Operation.DELETE, "ca"), Diff(Operation.EQUAL, "c"), Diff(Operation.DELETE, "b"), Diff(Operation.EQUAL, "a")];
    cleanupMerge(diffs);
    assert([Diff(Operation.EQUAL, "xca"), Diff(Operation.DELETE, "cba")] == diffs);
  }
}


void testDiffCleanupSemanticLossless() {
  // Slide diffs to match logical boundaries.
  {
    // Null case.
    Diff[] diffs = [];
    cleanupSemanticLossless(diffs);
    assert([] == diffs);
  }
  /*{
    // Blank lines.
    Diff[] diffs = [Diff(Operation.EQUAL, "AAA\r\n\r\nBBB"), Diff(Operation.INSERT, "\r\nDDD\r\n\r\nBBB"), Diff(Operation.EQUAL, "\r\nEEE")];
    assert([Diff(Operation.EQUAL, "AAA\r\n\r\n"), Diff(Operation.INSERT, "BBB\r\nDDD\r\n\r\n"), Diff(Operation.EQUAL, "BBB\r\nEEE")] == diffs);
  }
  */
  {
    // Line boundaries.
    Diff[] diffs = [Diff(Operation.EQUAL, "AAA\r\nBBB"), Diff(Operation.INSERT, " DDD\r\nBBB"), Diff(Operation.EQUAL, " EEE")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.EQUAL, "AAA\r\n"), Diff(Operation.INSERT, "BBB DDD\r\n"), Diff(Operation.EQUAL, "BBB EEE")] == diffs);
  }
  {
    // Word boundaries.
    Diff[] diffs = [Diff(Operation.EQUAL, "The c"), Diff(Operation.INSERT, "ow and the c"), Diff(Operation.EQUAL, "at.")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.EQUAL, "The "), Diff(Operation.INSERT, "cow and the "), Diff(Operation.EQUAL, "cat.")] == diffs);
  }
  {
    // Alphanumeric boundaries.
    Diff[] diffs = [Diff(Operation.EQUAL, "The-c"), Diff(Operation.INSERT, "ow-and-the-c"), Diff(Operation.EQUAL, "at.")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.EQUAL, "The-"), Diff(Operation.INSERT, "cow-and-the-"), Diff(Operation.EQUAL, "cat.")] == diffs);
  }
  {
    // Hitting the start.
    Diff[] diffs = [Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "a"), Diff(Operation.EQUAL, "ax")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.DELETE, "a"), Diff(Operation.EQUAL, "aax")] == diffs);
  }
  {
    // Hitting the end.
    Diff[] diffs = [Diff(Operation.EQUAL, "xa"), Diff(Operation.DELETE, "a"), Diff(Operation.EQUAL, "a")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.EQUAL, "xaa"), Diff(Operation.DELETE, "a")] == diffs);
  }
  {
    // Sentence boundaries.
    Diff[] diffs = [Diff(Operation.EQUAL, "The xxx. The "), Diff(Operation.INSERT, "zzz. The "), Diff(Operation.EQUAL, "yyy.")];
    cleanupSemanticLossless(diffs);
    assert([Diff(Operation.EQUAL, "The xxx."), Diff(Operation.INSERT, " The zzz."), Diff(Operation.EQUAL, " The yyy.")] == diffs);
  }
}

void testDiffCleanupSemantic() {
  // Cleanup semantically trivial equalities.
  // Null case.
  Diff[] diffs;
  cleanupSemantic(diffs);
  assertEquals([], diffs);

  // No elimination #1.
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "cd"), Diff(Operation.EQUAL, "12"), Diff(Operation.DELETE, "e")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "cd"), Diff(Operation.EQUAL, "12"), Diff(Operation.DELETE, "e")], diffs);

  // No elimination #2.
  diffs = [Diff(Operation.DELETE, "abc"), Diff(Operation.INSERT, "ABC"), Diff(Operation.EQUAL, "1234"), Diff(Operation.DELETE, "wxyz")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abc"), Diff(Operation.INSERT, "ABC"), Diff(Operation.EQUAL, "1234"), Diff(Operation.DELETE, "wxyz")], diffs);

  // Simple elimination.
  diffs = [Diff(Operation.DELETE, "a"), Diff(Operation.EQUAL, "b"), Diff(Operation.DELETE, "c")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abc"), Diff(Operation.INSERT, "b")], diffs);

  // Backpass elimination.
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.EQUAL, "cd"), Diff(Operation.DELETE, "e"), Diff(Operation.EQUAL, "f"), Diff(Operation.INSERT, "g")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abcdef"), Diff(Operation.INSERT, "cdfg")], diffs);

  // Multiple eliminations.
  diffs = [Diff(Operation.INSERT, "1"), Diff(Operation.EQUAL, "A"), Diff(Operation.DELETE, "B"), Diff(Operation.INSERT, "2"), Diff(Operation.EQUAL, "_"), Diff(Operation.INSERT, "1"), Diff(Operation.EQUAL, "A"), Diff(Operation.DELETE, "B"), Diff(Operation.INSERT, "2")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "AB_AB"), Diff(Operation.INSERT, "1A2_1A2")], diffs);

  // Word boundaries.
  diffs = [Diff(Operation.EQUAL, "The c"), Diff(Operation.DELETE, "ow and the c"), Diff(Operation.EQUAL, "at.")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.EQUAL, "The "), Diff(Operation.DELETE, "cow and the "), Diff(Operation.EQUAL, "cat.")], diffs);

  // No overlap elimination.
  diffs = [Diff(Operation.DELETE, "abcxx"), Diff(Operation.INSERT, "xxdef")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abcxx"), Diff(Operation.INSERT, "xxdef")], diffs);

  // Overlap elimination.
  diffs = [Diff(Operation.DELETE, "abcxxx"), Diff(Operation.INSERT, "xxxdef")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abc"), Diff(Operation.EQUAL, "xxx"), Diff(Operation.INSERT, "def")], diffs);

  // Reverse overlap elimination.
  diffs = [Diff(Operation.DELETE, "xxxabc"), Diff(Operation.INSERT, "defxxx")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.INSERT, "def"), Diff(Operation.EQUAL, "xxx"), Diff(Operation.DELETE, "abc")], diffs);

  // Two overlap eliminations.
  diffs = [Diff(Operation.DELETE, "abcd1212"), Diff(Operation.INSERT, "1212efghi"), Diff(Operation.EQUAL, "----"), Diff(Operation.DELETE, "A3"), Diff(Operation.INSERT, "3BC")];
  cleanupSemantic(diffs);
  assertEquals([Diff(Operation.DELETE, "abcd"), Diff(Operation.EQUAL, "1212"), Diff(Operation.INSERT, "efghi"), Diff(Operation.EQUAL, "----"), Diff(Operation.DELETE, "A"), Diff(Operation.EQUAL, "3"), Diff(Operation.INSERT, "BC")], diffs);
}

void testDiffCleanupEfficiency() {
  // Cleanup operationally trivial equalities.
  DIFF_EDIT_COST = 4;
  // Null case.
  Diff[] diffs;
  cleanupEfficiency(diffs);
  assertEquals([], diffs);

  // No elimination.
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "wxyz"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "34")];
  cleanupEfficiency(diffs);
  assertEquals([Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "wxyz"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "34")], diffs);

  // Four-edit elimination.
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "xyz"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "34")];
  cleanupEfficiency(diffs);
  assertEquals([Diff(Operation.DELETE, "abxyzcd"), Diff(Operation.INSERT, "12xyz34")], diffs);

  // Three-edit elimination.
  diffs = [Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "x"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "34")];
  cleanupEfficiency(diffs);
  assertEquals([Diff(Operation.DELETE, "xcd"), Diff(Operation.INSERT, "12x34")], diffs);

  // Backpass elimination.
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "xy"), Diff(Operation.INSERT, "34"), Diff(Operation.EQUAL, "z"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "56")];
  cleanupEfficiency(diffs);
  assertEquals([Diff(Operation.DELETE, "abxyzcd"), Diff(Operation.INSERT, "12xy34z56")], diffs);

  // High cost elimination.
  DIFF_EDIT_COST = 5;
  diffs = [Diff(Operation.DELETE, "ab"), Diff(Operation.INSERT, "12"), Diff(Operation.EQUAL, "wxyz"), Diff(Operation.DELETE, "cd"), Diff(Operation.INSERT, "34")];
  cleanupEfficiency(diffs);
  assertEquals([Diff(Operation.DELETE, "abwxyzcd"), Diff(Operation.INSERT, "12wxyz34")], diffs);
  DIFF_EDIT_COST = 4;
}

/*void testDiffPrettyHtml() {
  // Pretty print.
  auto diffs = [Diff(Operation.EQUAL, "a\n"), Diff(Operation.DELETE, "<B>b</B>"), Diff(Operation.INSERT, "c&d")];
  assertEquals(`<span>a&para;<br></span><del style="background:#ffe6e6;">&lt;B&gt;b&lt;/B&gt;</del><ins style="background:#e6ffe6;">c&amp;d</ins>`, prettyHtml(diffs));
}*/

void testDiffText() {
  // Compute the source and destination texts.
  auto diffs = [Diff(Operation.EQUAL, "jump"), Diff(Operation.DELETE, "s"), Diff(Operation.INSERT, "ed"), Diff(Operation.EQUAL, " over "), Diff(Operation.DELETE, "the"), Diff(Operation.INSERT, "a"), Diff(Operation.EQUAL, " lazy")];
  assertEquals(`jumps over the lazy`, diff_text1(diffs));

  assertEquals(`jumped over a lazy`, diff_text2(diffs));
}

void testDiffDelta() {
  // Convert a diff into delta string.
  auto diffs = [Diff(Operation.EQUAL, "jump"), Diff(Operation.DELETE, "s"), Diff(Operation.INSERT, "ed"), Diff(Operation.EQUAL, " over "), Diff(Operation.DELETE, "the"), Diff(Operation.INSERT, "a"), Diff(Operation.EQUAL, " lazy"), Diff(Operation.INSERT, "old dog")];
  auto text1 = diff_text1(diffs);
  assertEquals(`jumps over the lazy`, text1);

  auto delta = toDelta(diffs);
  assertEquals("=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta);

  // Convert delta string into a diff.
  assertEquals(diffs, fromDelta(text1, delta));

  // Generates error (19 != 20)
  assertThrown(fromDelta(text1 ~ `x`, delta));

  // Generates error (19 != 18).
  assertThrown(fromDelta(text1[1 .. $], delta));

  // Generates error (%c3%xy invalid Unicode).
  assertThrown(fromDelta(``, `+%c3%xy`));

  // Test deltas with special characters.
  diffs = [Diff(Operation.EQUAL, "\u0680 \x00 \t %"), Diff(Operation.DELETE, "\u0681 \x01 \n ^"), Diff(Operation.INSERT, "\u0682 \x02 \\ |")];
  text1 = diff_text1(diffs);
  assertEquals("\u0680 \x00 \t %\u0681 \x01 \n ^", text1);

  delta = toDelta(diffs);
  assertEquals("=7\t-7\t+%DA%82 %02 %5C %7C", delta);

  // Convert delta string into a diff.
  assertEquals(diffs, fromDelta(text1, delta));

  // Verify pool of unchanged characters.
  diffs = [Diff(Operation.INSERT, "A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ")];
  auto text2 = diff_text2(diffs);
  assertEquals("A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", text2);

  delta = toDelta(diffs);
  assertEquals("+A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", delta);

  // Convert delta string into a diff.
  assertEquals(diffs, fromDelta("", delta));
}

void testDiffXIndex() {
  // Translate a location in text1 to text2.
  // Translation on equality.
  assertEquals(5, xIndex([Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "1234"), Diff(Operation.EQUAL, "xyz")], 2));

  // Translation on deletion.
  assertEquals(1, xIndex([Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "1234"), Diff(Operation.EQUAL, "xyz")], 3));
}

void testDiffLevenshtein() {
  // Levenshtein with trailing equality.
  assertEquals(4, levenshtein([Diff(Operation.DELETE, "abc"), Diff(Operation.INSERT, "1234"), Diff(Operation.EQUAL, "xyz")]));
  // Levenshtein with leading equality.
  assertEquals(4, levenshtein([Diff(Operation.EQUAL, "xyz"), Diff(Operation.DELETE, "abc"), Diff(Operation.INSERT, "1234")]));
  // Levenshtein with middle equality.
  assertEquals(7, levenshtein([Diff(Operation.DELETE, "abc"), Diff(Operation.EQUAL, "xyz"), Diff(Operation.INSERT, "1234")]));
}

void testDiffBisect() {
  // Normal.
  auto a = "cat";
  auto b = "map";
  // Since the resulting diff hasn't been normalized, it would be ok if
  // the insertion and deletion pairs are swapped.
  // If the order changes, tweak this test as required.
  assertEquals([Diff(Operation.DELETE, "c"), Diff(Operation.INSERT, "m"), Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "t"), Diff(Operation.INSERT, "p")], bisect(a, b, SysTime.max));

  // Timeout.
  assertEquals([Diff(Operation.DELETE, "cat"), Diff(Operation.INSERT, "map")], bisect(a, b, SysTime(0)));
}

void testDiffMain() {
  // Perform a trivial diff.
  // Null case.
  assertEquals([], diff_main("", "", false));

  // Equality.
  assertEquals([Diff(Operation.EQUAL, "abc")], diff_main("abc", "abc", false));

  // Simple insertion.
  assertEquals([Diff(Operation.EQUAL, "ab"), Diff(Operation.INSERT, "123"), Diff(Operation.EQUAL, "c")], diff_main("abc", "ab123c", false));

  // Simple deletion.
  assertEquals([Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "123"), Diff(Operation.EQUAL, "bc")], diff_main("a123bc", "abc", false));

  // Two insertions.
  assertEquals([Diff(Operation.EQUAL, "a"), Diff(Operation.INSERT, "123"), Diff(Operation.EQUAL, "b"), Diff(Operation.INSERT, "456"), Diff(Operation.EQUAL, "c")], diff_main("abc", "a123b456c", false));

  // Two deletions.
  assertEquals([Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "123"), Diff(Operation.EQUAL, "b"), Diff(Operation.DELETE, "456"), Diff(Operation.EQUAL, "c")], diff_main("a123b456c", "abc", false));

  // Perform a real diff.
  // Switch off the timeout.
  diffTimeout = 0.seconds;
  // Simple cases.
  assertEquals([Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "b")], diff_main("a", "b", false));

  assertEquals([Diff(Operation.DELETE, "Apple"), Diff(Operation.INSERT, "Banana"), Diff(Operation.EQUAL, "s are a"), Diff(Operation.INSERT, "lso"), Diff(Operation.EQUAL, " fruit.")], diff_main("Apples are a fruit.", "Bananas are also fruit.", false));

  assertEquals([Diff(Operation.DELETE, "a"), Diff(Operation.INSERT, "\u0680"), Diff(Operation.EQUAL, "x"), Diff(Operation.DELETE, "\t"), Diff(Operation.INSERT, "\0")], diff_main("ax\t", "\u0680x\0", false));

  // Overlaps.
  assertEquals([Diff(Operation.DELETE, "1"), Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "y"), Diff(Operation.EQUAL, "b"), Diff(Operation.DELETE, "2"), Diff(Operation.INSERT, "xab")], diff_main("1ayb2", "abxab", false));

  assertEquals([Diff(Operation.INSERT, "xaxcx"), Diff(Operation.EQUAL, "abc"), Diff(Operation.DELETE, "y")], diff_main("abcy", "xaxcxabc", false));

  assertEquals([Diff(Operation.DELETE, "ABCD"), Diff(Operation.EQUAL, "a"), Diff(Operation.DELETE, "="), Diff(Operation.INSERT, "-"), Diff(Operation.EQUAL, "bcd"), Diff(Operation.DELETE, "="), Diff(Operation.INSERT, "-"), Diff(Operation.EQUAL, "efghijklmnopqrs"), Diff(Operation.DELETE, "EFGHIJKLMNOefg")], diff_main("ABCDa=bcd=efghijklmnopqrsEFGHIJKLMNOefg", "a-bcd-efghijklmnopqrs", false));

  // Large equality.
  assertEquals([Diff(Operation.INSERT, " "), Diff(Operation.EQUAL, "a"), Diff(Operation.INSERT, "nd"), Diff(Operation.EQUAL, " [[Pennsylvania]]"), Diff(Operation.DELETE, " and [[New")], diff_main("a [[Pennsylvania]] and [[New", " and [[Pennsylvania]]", false));

  // Timeout.
  diffTimeout = 100.msecs;
  auto a = "`Twas brillig, and the slithy toves\nDid gyre and gimble in the wabe:\nAll mimsy were the borogoves,\nAnd the mome raths outgrabe.\n";
  auto b = "I am the very model of a modern major general,\nI\'ve information vegetable, animal, and mineral,\nI know the kings of England, and I quote the fights historical,\nFrom Marathon to Waterloo, in order categorical.\n";
  // Increase the text lengths by 1024 times to ensure a timeout.
  foreach (x; 0 .. 10) {
    a = a ~ a;
    b = b ~ b;
  }
  auto startTime = Clock.currTime(UTC());
  diff_main(a, b);
  auto endTime = Clock.currTime(UTC());
  // Test that we took at least the timeout period.
  assert(diffTimeout <= endTime - startTime);
  // Test that we didn't take forever (be forgiving).
  // Theoretically this test could fail very occasionally if the
  // OS task swaps or locks up for a second at the wrong moment.
  // ****
  // TODO(fraser): For unknown reasons this is taking 500 ms on Google's
  // internal test system.  Whereas browsers take 140 ms.
  //assert(dmp.Diff_Timeout * 1000 * 2 > endTime - startTime);
  // ****
  diffTimeout = 0.seconds;

  // Test the linemode speedup.
  // Must be long to pass the 100 char cutoff.
  // Simple line-mode.
  a = "1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n";
  b = "abcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\nabcdefghij\n";
  assertEquals(diff_main(a, b, false), diff_main(a, b, true));

  // Single line-mode.
  a = "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890";
  b = "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij";
  assertEquals(diff_main(a, b, false), diff_main(a, b, true));

  // Overlap line-mode.
  a = "1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n1234567890\n";
  b = "abcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n";
  auto texts_linemode = diff_rebuildtexts(diff_main(a, b, true));
  auto texts_textmode = diff_rebuildtexts(diff_main(a, b, false));
  assertEquals(texts_textmode, texts_linemode);

  // Test line-mode compression running out of UTF-8 space
  import std.conv;
  a = "";
  b = "";
  foreach (x; 0 .. 500) {
      a ~= "1234567890" ~ to!string(x) ~ "\n";
      b ~= "abcdefghij" ~ to!string(x) ~ "\n";
  }
  try {
      assertEquals(diff_main(a, b, false), diff_main(a, b, true));
      assert(false, "Expected exception when unique lines exceeds UTF-8 encoding space.");
  } catch (Exception e) {
      // ignore
  }

  // Test using UTF-16 to handle cases when UTF-8 would run out of space.
  wstring a2 = "";
  wstring b2 = "";
  foreach (x; 0 .. 500) {
      a2 ~= "1234567890" ~ to!wstring(x) ~ "\n";
      b2 ~= "abcdefghij" ~ to!wstring(x) ~ "\n";
  }
  assertEquals(diff_main(a2, b2, false), diff_main(a2, b2, true));

  // (Don't) Test null inputs (not needed in D, because null is a valid empty string)
  //assertThrown(diff_main(null, null));
}


// MATCH TEST FUNCTIONS


void testMatchAlphabet() {
  // Initialise the bitmasks for Bitap.
  // Unique.
  assertEquals(['a':4, 'b':2, 'c':1], initAlphabet("abc"));

  // Duplicates.
  assertEquals(['a':37, 'b':18, 'c':8], initAlphabet("abcaba"));
}

void testMatchBitap() {
  // Bitap algorithm.
  MATCH_DISTANCE = 100;
  MATCH_THRESHOLD = 0.5;
  // Exact matches.
  assertEquals(5, bitap("abcdefghijk", "fgh", 5));

  assertEquals(5, bitap("abcdefghijk", "fgh", 0));

  // Fuzzy matches.
  assertEquals(4, bitap("abcdefghijk", "efxhi", 0));

  assertEquals(2, bitap("abcdefghijk", "cdefxyhijk", 5));

  assertEquals(-1, bitap("abcdefghijk", "bxy", 1));

  // Overflow.
  assertEquals(2, bitap("123456789xx0", "3456789x0", 2));

  // Threshold test.
  MATCH_THRESHOLD = 0.4;
  assertEquals(4, bitap("abcdefghijk", "efxyhi", 1));

  MATCH_THRESHOLD = 0.3;
  assertEquals(-1, bitap("abcdefghijk", "efxyhi", 1));

  MATCH_THRESHOLD = 0.0;
  assertEquals(1, bitap("abcdefghijk", "bcdef", 1));
  MATCH_THRESHOLD = 0.5;

  // Multiple select.
  assertEquals(0, bitap("abcdexyzabcde", "abccde", 3));

  assertEquals(8, bitap("abcdexyzabcde", "abccde", 5));

  // Distance test.
  MATCH_DISTANCE = 10;  // Strict location.
  assertEquals(-1, bitap("abcdefghijklmnopqrstuvwxyz", "abcdefg", 24));

  assertEquals(0, bitap("abcdefghijklmnopqrstuvwxyz", "abcdxxefg", 1));

  MATCH_DISTANCE = 1000;  // Loose location.
  assertEquals(0, bitap("abcdefghijklmnopqrstuvwxyz", "abcdefg", 24));
}

void testMatchMain() {
  // Full match.
  // Shortcut matches.
  assertEquals(0, match_main("abcdef", "abcdef", 1000));

  assertEquals(-1, match_main("", "abcdef", 1));

  assertEquals(3, match_main("abcdef", "", 3));

  assertEquals(3, match_main("abcdef", "de", 3));

  // Beyond end match.
  assertEquals(3, match_main("abcdef", "defy", 4));

  // Oversized pattern.
  assertEquals(0, match_main("abcdef", "abcdefy", 0));

  // Complex match.
  assertEquals(4, match_main("I am the very model of a modern major general.", " that berry ", 5));

  // (Don't) test null inputs. (not needed in D because null is a valid empty string)
  //assertThrown(match_main(null, null, 0));
}


// PATCH TEST FUNCTIONS


void testPatchObj() {
  // Patch Object.
  Patch p;
  p.start1 = 20;
  p.start2 = 21;
  p.length1 = 18;
  p.length2 = 17;
  p.diffs = [Diff(Operation.EQUAL, "jump"), Diff(Operation.DELETE, "s"), Diff(Operation.INSERT, "ed"), Diff(Operation.EQUAL, " over "), Diff(Operation.DELETE, "the"), Diff(Operation.INSERT, "a"), Diff(Operation.EQUAL, "\nlaz")];
  auto strp = p.toString();
  assertEquals("@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n", strp);
}

void testPatchFromText() {
  string strp;
  assertEquals([], patch_fromText(strp));

  strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";
  assertEquals(strp, patch_fromText(strp)[0].toString());

  assertEquals("@@ -1 +1 @@\n-a\n+b\n", patch_fromText("@@ -1 +1 @@\n-a\n+b\n")[0].toString());

  assertEquals("@@ -1,3 +0,0 @@\n-abc\n", patch_fromText("@@ -1,3 +0,0 @@\n-abc\n")[0].toString());

  assertEquals("@@ -0,0 +1,3 @@\n+abc\n", patch_fromText("@@ -0,0 +1,3 @@\n+abc\n")[0].toString());

  // Generates error.
  assertThrown(patch_fromText("Bad\nPatch\n"));
}

void testPatchToText() {
  auto strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
  auto p = patch_fromText(strp);
  assertEquals(strp, patch_toText(p));

  strp = "@@ -1,9 +1,9 @@\n-f\n+F\n oo+fooba\n@@ -7,9 +7,9 @@\n obar\n-,\n+.\n  tes\n";
  p = patch_fromText(strp);
  assertEquals(strp, patch_toText(p));
}

void testPatchAddContext() {
  PATCH_MARGIN = 4;
  auto p = patch_fromText("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0];
  addContext(p, "The quick brown fox jumps over the lazy dog.");
  assertEquals("@@ -17,12 +17,18 @@\n fox \n-jump\n+somersault\n s ov\n", p.toString());

  // Same, but not enough trailing context.
  p = patch_fromText("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0];
  addContext(p, "The quick brown fox jumps.");
  assertEquals("@@ -17,10 +17,16 @@\n fox \n-jump\n+somersault\n s.\n", p.toString());

  // Same, but not enough leading context.
  p = patch_fromText("@@ -3 +3,2 @@\n-e\n+at\n")[0];
  addContext(p, "The quick brown fox jumps.");
  assertEquals("@@ -1,7 +1,8 @@\n Th\n-e\n+at\n  qui\n", p.toString());

  // Same, but with ambiguity.
  p = patch_fromText("@@ -3 +3,2 @@\n-e\n+at\n")[0];
  addContext(p, "The quick brown fox jumps.  The quick brown fox crashes.");
  assertEquals("@@ -1,27 +1,28 @@\n Th\n-e\n+at\n  quick brown fox jumps. \n", p.toString());
}

void testPatchMake() {
  // Null case.
  auto patches = patch_make("", "");
  assertEquals("", patch_toText(patches));

  auto text1 = "The quick brown fox jumps over the lazy dog.";
  auto text2 = "That quick brown fox jumped over a lazy dog.";
  // Text2+Text1 inputs.
  auto expectedPatch = "@@ -1,8 +1,7 @@\n Th\n-at\n+e\n  qui\n@@ -21,17 +21,18 @@\n jump\n-ed\n+s\n  over \n-a\n+the\n  laz\n";
  // The second patch must be "-21,17 +21,18", not "-22,17 +21,18" due to rolling context.
  patches = patch_make(text2, text1);
  assertEquals(expectedPatch, patch_toText(patches));

  // Text1+Text2 inputs.
  expectedPatch = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
  patches = patch_make(text1, text2);
  assertEquals(expectedPatch, patch_toText(patches));

  // Diff input.
  auto diffs = diff_main(text1, text2, false);
  patches = patch_make(diffs);
  assertEquals(expectedPatch, patch_toText(patches));

  // Text1+Diff inputs.
  patches = patch_make(text1, diffs);
  assertEquals(expectedPatch, patch_toText(patches));

  // Text1+Text2+Diff inputs (deprecated).
  //patches = patch_make(text1, text2, diffs);
  //assertEquals(expectedPatch, patch_toText(patches));

  // Character encoding.
  //patches = patch_make("`1234567890-=[]\\;',./', '~!@#$%^&*()_+{}|:\"<>?");
  //assertEquals("@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n", patch_toText(patches));
  // FIXME: enable test ^

  // Character decoding.
  diffs = [Diff(Operation.DELETE, "`1234567890-=[]\\;\',./"), Diff(Operation.INSERT, "~!@#$%^&*()_+{}|:\"<>?")];
  assertEquals(diffs, patch_fromText("@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n")[0].diffs);

  // Long string with repeats.
  text1 = "";
  foreach (x; 0 .. 100) {
    text1 ~= "abcdef";
  }
  text2 = text1 ~ "123";
  expectedPatch = "@@ -573,28 +573,31 @@\n cdefabcdefabcdefabcdefabcdef\n+123\n";
  patches = patch_make(text1, text2);
  assertEquals(expectedPatch, patch_toText(patches));

  // (Don't) Test null inputs. (not needed in D because null is a valid empty string)
  //assertThrown(patch_make!string(null));
}

void testPatchSplitMax() {
  // Assumes that dmp.Match_MaxBits is 32.
  auto patches = patch_make("abcdefghijklmnopqrstuvwxyz01234567890", "XabXcdXefXghXijXklXmnXopXqrXstXuvXwxXyzX01X23X45X67X89X0");
  splitMax(patches);
  assertEquals("@@ -1,32 +1,46 @@\n+X\n ab\n+X\n cd\n+X\n ef\n+X\n gh\n+X\n ij\n+X\n kl\n+X\n mn\n+X\n op\n+X\n qr\n+X\n st\n+X\n uv\n+X\n wx\n+X\n yz\n+X\n 012345\n@@ -25,13 +39,18 @@\n zX01\n+X\n 23\n+X\n 45\n+X\n 67\n+X\n 89\n+X\n 0\n", patch_toText(patches));

  patches = patch_make("abcdef1234567890123456789012345678901234567890123456789012345678901234567890uvwxyz", "abcdefuvwxyz");
  auto oldToText = patch_toText(patches);
  splitMax(patches);
  assertEquals(oldToText, patch_toText(patches));

  patches = patch_make("1234567890123456789012345678901234567890123456789012345678901234567890", "abc");
  splitMax(patches);
  assertEquals("@@ -1,32 +1,4 @@\n-1234567890123456789012345678\n 9012\n@@ -29,32 +1,4 @@\n-9012345678901234567890123456\n 7890\n@@ -57,14 +1,3 @@\n-78901234567890\n+abc\n", patch_toText(patches));

  //patches = patch_make("abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1', 'abcdefghij , h : 1 , t : 1 abcdefghij , h : 1 , t : 1 abcdefghij , h : 0 , t : 1");
  //splitMax(patches);
  //assertEquals("@@ -2,32 +2,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n@@ -29,32 +29,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n", patch_toText(patches));
  // FIXME: enable test ^
}

void testPatchAddPadding() {
  // Both edges full.
  auto patches = patch_make("", "test");
  assertEquals("@@ -0,0 +1,4 @@\n+test\n", patch_toText(patches));
  addPadding(patches);
  assertEquals("@@ -1,8 +1,12 @@\n %01%02%03%04\n+test\n %01%02%03%04\n", patch_toText(patches));

  // Both edges partial.
  patches = patch_make("XY", "XtestY");
  assertEquals("@@ -1,2 +1,6 @@\n X\n+test\n Y\n", patch_toText(patches));
  addPadding(patches);
  assertEquals("@@ -2,8 +2,12 @@\n %02%03%04X\n+test\n Y%01%02%03\n", patch_toText(patches));

  // Both edges none.
  patches = patch_make("XXXXYYYY", "XXXXtestYYYY");
  assertEquals("@@ -1,8 +1,12 @@\n XXXX\n+test\n YYYY\n", patch_toText(patches));
  addPadding(patches);
  assertEquals("@@ -5,8 +5,12 @@\n XXXX\n+test\n YYYY\n", patch_toText(patches));
}

void testPatchApply() {
  MATCH_DISTANCE = 1000;
  MATCH_THRESHOLD = 0.5;
  PATCH_DELETE_THRESHOLD = 0.5;
  // Null case.
  auto patches = patch_make("", "");
  auto results = apply(patches, "Hello world.");
  assertEquals(PatchApplyResult("Hello world.", []), results);

  // Exact match.
  patches = patch_make("The quick brown fox jumps over the lazy dog.", "That quick brown fox jumped over a lazy dog.");
  results = apply(patches, "The quick brown fox jumps over the lazy dog.");
  assertEquals(PatchApplyResult("That quick brown fox jumped over a lazy dog.", [true, true]), results);

  // Partial match.
  results = apply(patches, "The quick red rabbit jumps over the tired tiger.");
  assertEquals(PatchApplyResult("That quick red rabbit jumped over a tired tiger.", [true, true]), results);

  // Failed match.
  results = apply(patches, "I am the very model of a modern major general.");
  assertEquals(PatchApplyResult("I am the very model of a modern major general.", [false, false]), results);

  // Big delete, small change.
  patches = patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
  results = apply(patches, "x123456789012345678901234567890-----++++++++++-----123456789012345678901234567890y");
  assertEquals(PatchApplyResult("xabcy", [true, true]), results);

  // Big delete, big change 1.
  patches = patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
  results = apply(patches, "x12345678901234567890---------------++++++++++---------------12345678901234567890y");
  assertEquals(PatchApplyResult("xabc12345678901234567890---------------++++++++++---------------12345678901234567890y", [false, true]), results);

  // Big delete, big change 2.
  PATCH_DELETE_THRESHOLD = 0.6;
  patches = patch_make("x1234567890123456789012345678901234567890123456789012345678901234567890y", "xabcy");
  results = apply(patches, "x12345678901234567890---------------++++++++++---------------12345678901234567890y");
  assertEquals(PatchApplyResult("xabcy", [true, true]), results);
  PATCH_DELETE_THRESHOLD = 0.5;

  // Compensate for failed patch.
  MATCH_THRESHOLD = 0.0;
  MATCH_DISTANCE = 0;
  patches = patch_make("abcdefghijklmnopqrstuvwxyz--------------------1234567890", "abcXXXXXXXXXXdefghijklmnopqrstuvwxyz--------------------1234567YYYYYYYYYY890");
  results = apply(patches, "ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567890");
  assertEquals(PatchApplyResult("ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567YYYYYYYYYY890", [false, true]), results);
  MATCH_THRESHOLD = 0.5;
  MATCH_DISTANCE = 1000;

  // No side effects.
  patches = patch_make("", "test");
  auto patchstr = patch_toText(patches);
  apply(patches, "");
  assertEquals(patchstr, patch_toText(patches));

  // No side effects with major delete.
  patches = patch_make("The quick brown fox jumps over the lazy dog.", "Woof");
  patchstr = patch_toText(patches);
  apply(patches, "The quick brown fox jumps over the lazy dog.");
  assertEquals(patchstr, patch_toText(patches));

  // Edge exact match.
  patches = patch_make("", "test");
  results = apply(patches, "");
  assertEquals(PatchApplyResult("test", [true]), results);

  // Near edge exact match.
  patches = patch_make("XY", "XtestY");
  results = apply(patches, "XY");
  assertEquals(PatchApplyResult("XtestY", [true]), results);

  // Edge partial match.
  patches = patch_make("y", "y123");
  results = apply(patches, "x");
  assertEquals(PatchApplyResult("x123", [true]), results);
}

string[] diff_rebuildtexts(Diff[] diffs) {
  string[] text = ["", ""];

  foreach (myDiff; diffs) {
    if (myDiff.operation != Operation.INSERT) {
      text[0] ~= myDiff.text;
    }
    if (myDiff.operation != Operation.DELETE) {
      text[1] ~= myDiff.text;
    }
  }
  return text;
}

void assertEquals(T, U)(T t, U u, string file = __FILE__, int line = __LINE__)
{
  import core.exception : AssertError;
  import std.string : format;
  if (t != u)
    throw new AssertError(format("%s does not match %s", t, u), file, line);
}

void main()
{
	testDiffCommonPrefix();
	testDiffCommonSuffix();
	testDiffCommonOverlap();
	testDiffHalfMatch();
  testDiffLinesToChars();
  testDiffCleanupMerge();
  testDiffCleanupSemanticLossless();
  testDiffCleanupSemantic();
  testDiffCleanupEfficiency();
  //testDiffPrettyHtml(); // FIXME: implement HTML output
  testDiffText();
  testDiffDelta();
  testDiffXIndex();
  testDiffLevenshtein();
  testDiffBisect();
  testDiffMain();
  testMatchAlphabet();
  testMatchBitap();
  testMatchMain();
  testPatchObj();
  testPatchFromText();
  testPatchToText();
  testPatchAddContext();
  testPatchMake();
  testPatchSplitMax();
  testPatchAddPadding();
  testPatchApply();
	writeln("All test passed");
}
