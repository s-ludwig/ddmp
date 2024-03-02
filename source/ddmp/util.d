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
module ddmp.util;

import std.traits : isSomeString;
import std.string : indexOf;

Range substr(Range)(Range str, size_t start, size_t len = size_t.max)
if (isSomeString!Range) {
    auto end = len == size_t.max ? str.length : start + len;
    if (start >= str.length) {
        return "";
    }
    if (end > str.length) {
        end = str.length;
    }
    return str[start..end];
}

sizediff_t indexOfAlt(Range)(Range str, Range search, sizediff_t offset=0)
if (isSomeString!Range) {
    auto index = str[offset..$].indexOf(search);
    if (index > -1 ) return index + offset;
    return -1;
}

void insert(T)( ref T[] array, size_t i, T[] stuff)
{
    array = array[0..i] ~ stuff ~ array[i..$];
}
void remove(T)( ref T[] array, size_t i, size_t count=1)
{
    array = array[0..i] ~ array[i+count..$];
}

T[] splice(T)(ref T[] list, sizediff_t start, sizediff_t count, T[] objects=null) {
    T[] deletedRange = list[start..start+count];
    list = list[0 .. start] ~ objects ~ list[start+count .. $];
    return deletedRange;
}
