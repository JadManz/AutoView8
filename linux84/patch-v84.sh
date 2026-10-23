#!/usr/bin/env bash
# patch-v84.sh View8 V8 change, rewrite of V8 8.4.371.22
#
# usage:  bash patch-v84.sh /path/to/v8
#
# V8 targets 10+; the script below makes similiar changes but instead finds each spot by text and not ln number.

set -euo pipefail
V8=${1:?give the V8 source folder, e.g. ~/v8work/v8}
cd "$V8"

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

rep $F '    os << Brief(GetCode());
  }
  PrintSourceCode(os);
' '    os << Brief(GetCode());
  }
'

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

echo "== 3. src/objects/string.cc"
F=src/objects/string.cc

rep $F '  int len = length();
  if (len > kMaxShortPrintLength) {
    accumulator->Add("<Very long string[%s%u]>", internalized_marker, len);
    return;
  }
' '  int len = length();
'

rep $F '  bool truncated = false;
  if (len > kMaxShortPrintLength) {
    len = kMaxShortPrintLength;
    truncated = true;
  }
' '  bool truncated = false;
'

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
