#!/usr/bin/env bash
# patch-v84.sh - View8's V8 changes, rewritten for V8 8.4.371.22.
#
# usage:  bash patch-v84.sh /path/to/v8
#
# View8's own v8.patch targets V8 10+, so it can't apply to 8.4.
# This script makes the same changes, but finds each spot by its exact
# text instead of by line number. If a spot isn't found exactly once,
# it stops with a clear message instead of guessing.
#
# What the changes do (same idea as View8):
#   1. objects-printer.cc  a function prints its bytecode, not its source
#   2. objects.cc          arrays, object literals and inner functions
#                          print their full contents, not just a label
#   3. string.cc           strings print in full (no "...<truncated>"),
#                          in the "<String[5]: #hello>" form View8 reads
#   4. code-serializer.cc  print everything right after loading app.bin,
#                          and skip the "is this cache for this script?"
#                          check (it never is - we give a dummy script)
#   5. deserializer.cc     don't crash on the magic-number check

set -euo pipefail
V8=${1:?give the V8 source folder, e.g. ~/v8work/v8}
cd "$V8"

# rep FILE OLD NEW : replace the exact text OLD with NEW, exactly once.
rep() {
  F="$1" OLD="$2" NEW="$3" perl -e '
    my ($f, $old, $new) = @ENV{qw(F OLD NEW)};
    open my $h, "<", $f or die "cannot read $f\n";
    my $s = do { local $/; <$h> }; close $h;
    my ($n, $at) = (0, 0);
    while (($at = index($s, $old, $at)) >= 0) { $n++; $at += length $old }
    if ($n != 1) {
      print STDERR "\nPATCH FAILED in $f: expected this text once, found it $n times:\n$old\n";
      exit 1;
    }
    substr($s, index($s, $old), length $old) = $new;
    open $h, ">", $f or die "cannot write $f\n"; print $h $s; close $h;
  '
  echo "  ok  $1"
}

echo "== 1. src/diagnostics/objects-printer.cc"
F=src/diagnostics/objects-printer.cc

# Don't print source code (we only have a dummy source - it would crash).
rep $F '    os << Brief(GetCode());
  }
  PrintSourceCode(os);
' '    os << Brief(GetCode());
  }
'

# At the end of SharedFunctionInfoPrint, print the bytecode.
rep $F '    feedback_metadata().FeedbackMetadataPrint(os);
  } else {
    os << "<none>";
  }
  os << "\n";
}

void JSGlobalProxy::JSGlobalProxyPrint' '    feedback_metadata().FeedbackMetadataPrint(os);
  } else {
    os << "<none>";
  }
  os << "\n";
  os << "\nStart BytecodeArray\n";
  if (HasBytecodeArray()) {
    GetBytecodeArray().Disassemble(os);
  } else {
    os << "<no bytecode: this function was never compiled>\n";
  }
  os << "\nEnd BytecodeArray\n";
  os << std::flush;
}

void JSGlobalProxy::JSGlobalProxyPrint'

echo "== 2. src/objects/objects.cc"
F=src/objects/objects.cc

rep $F '    case FIXED_ARRAY_TYPE:
      os << "<FixedArray[" << FixedArray::cast(*this).length() << "]>";
      break;' '    case FIXED_ARRAY_TYPE:
      os << "<FixedArray[" << FixedArray::cast(*this).length() << "]>";
      os << "\nStart FixedArray\n";
      FixedArray::cast(*this).FixedArrayPrint(os);
      os << "\nEnd FixedArray\n";
      break;'

rep $F '    case OBJECT_BOILERPLATE_DESCRIPTION_TYPE:
      os << "<ObjectBoilerplateDescription[" << FixedArray::cast(*this).length()
         << "]>";
      break;' '    case OBJECT_BOILERPLATE_DESCRIPTION_TYPE:
      os << "<ObjectBoilerplateDescription[" << FixedArray::cast(*this).length()
         << "]>";
      os << "\nStart ObjectBoilerplateDescription\n";
      ObjectBoilerplateDescription::cast(*this)
          .ObjectBoilerplateDescriptionPrint(os);
      os << "\nEnd ObjectBoilerplateDescription\n";
      break;'

rep $F '    case FIXED_DOUBLE_ARRAY_TYPE:
      os << "<FixedDoubleArray[" << FixedDoubleArray::cast(*this).length()
         << "]>";
      break;' '    case FIXED_DOUBLE_ARRAY_TYPE:
      os << "<FixedDoubleArray[" << FixedDoubleArray::cast(*this).length()
         << "]>";
      os << "\nStart FixedDoubleArray\n";
      FixedDoubleArray::cast(*this).FixedDoubleArrayPrint(os);
      os << "\nEnd FixedDoubleArray\n";
      break;'

# Inner functions: print the whole function, not just its name.
rep $F '        os << "<SharedFunctionInfo>";
      }
      break;
    }' '        os << "<SharedFunctionInfo>";
      }
      os << "\nStart SharedFunctionInfo\n";
      shared.SharedFunctionInfoPrint(os);
      os << "\nEnd SharedFunctionInfo\n";
      break;
    }'

# (View8 also adds an ArrayBoilerplateDescription hack here. Not needed in
#  8.4: it already prints its inner array, which edit 2 now prints in full.)

echo "== 3. src/objects/string.cc"
F=src/objects/string.cc

# No "<Very long string[1234]>" - print it.
rep $F '  int len = length();
  if (len > kMaxShortPrintLength) {
    accumulator->Add("<Very long string[%s%u]>", internalized_marker, len);
    return;
  }
' '  int len = length();
'

# No cutting at 1024 characters.
rep $F '  bool truncated = false;
  if (len > kMaxShortPrintLength) {
    len = kMaxShortPrintLength;
    truncated = true;
  }
' '  bool truncated = false;
'

# 8.4 prints <String[#5]: hello>, View8 expects <String[5]: #hello>.
rep $F '      accumulator->Add("<String[%s%u]: ", internalized_marker, length());' \
       '      accumulator->Add("<String[%u]: %s", length(), internalized_marker);'
rep $F '      accumulator->Add("<String[%s%u]\\: ", internalized_marker, length());' \
       '      accumulator->Add("<String[%u]\\: %s", length(), internalized_marker);'

echo "== 4. src/snapshot/code-serializer.cc"
F=src/snapshot/code-serializer.cc

rep $F '#include "src/snapshot/code-serializer.h"
' '#include "src/snapshot/code-serializer.h"

#include <iostream>
'

# Right after app.bin is loaded: print the top-level function (which
# prints everything inside it).
rep $F '    if (FLAG_profile_deserialization) PrintF("[Deserializing failed]\n");
    return MaybeHandle<SharedFunctionInfo>();
  }
' '    if (FLAG_profile_deserialization) PrintF("[Deserializing failed]\n");
    return MaybeHandle<SharedFunctionInfo>();
  }

  std::cout << "\nStart SharedFunctionInfo\n";
  result->SharedFunctionInfoPrint(std::cout);
  std::cout << "\nEnd SharedFunctionInfo\n";
  std::cout << std::flush;
'

# Skip the checks, but print what they would have compared. If "magic"
# or "version" differ, this V8 build doesn't match the game's V8.
rep $F 'SerializedCodeData::SanityCheckResult SerializedCodeData::SanityCheck(
    uint32_t expected_source_hash) const {
  if (this->size_ < kHeaderSize) return INVALID_HEADER;
' 'SerializedCodeData::SanityCheckResult SerializedCodeData::SanityCheck(
    uint32_t expected_source_hash) const {
  if (this->size_ < kHeaderSize) return INVALID_HEADER;
  std::cout << std::hex
            << "[v8dasm] magic   file=0x" << GetMagicNumber()
            << "  this build=0x" << static_cast<uint32_t>(kMagicNumber) << "\n"
            << "[v8dasm] version file=0x" << GetHeaderValue(kVersionHashOffset)
            << "  this build=0x" << Version::Hash() << "\n"
            << "[v8dasm] flags   file=0x" << GetHeaderValue(kFlagHashOffset)
            << "  this build=0x" << FlagList::Hash() << "\n"
            << std::dec << std::flush;
  return CHECK_SUCCESS;  // the original checks below are now skipped
'

echo "== 5. src/snapshot/deserializer.cc"
F=src/snapshot/deserializer.cc
rep $F '  CHECK_EQ(magic_number_, SerializedData::kMagicNumber);
' ''

echo "All V8 8.4 edits applied."
