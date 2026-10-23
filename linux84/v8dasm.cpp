// v8dasm.cpp dasm for (NW.js 0.47.2)

#include <cstdio>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

#include "include/libplatform/libplatform.h"
#include "include/v8.h"


static const char kTestJs[] =
    "var clips = { '8020-8120': 42.833, start: [1, 2, 3], d: [1.5, 2.25] };\n"
    "function govid(name) {\n"
    "  try { if (clips[name] > 1) return name + '!'; }\n"
    "  catch (e) { return null; }\n"
    "  switch (name) { case 'a': return 1; case 'b': return 2; }\n"
    "  return 'x';\n"
    "}\n"
    "for (var i = 0; i < 3; i++) govid('a' + i);\n";

static int MakeTest(v8::Isolate* isolate, const char* out_path) {
  v8::ScriptOrigin origin(v8::String::NewFromUtf8Literal(isolate, "test.js"));
  v8::ScriptCompiler::Source source(
      v8::String::NewFromUtf8Literal(isolate, kTestJs), origin);
  v8::Local<v8::UnboundScript> script;
  if (!v8::ScriptCompiler::CompileUnboundScript(
           isolate, &source, v8::ScriptCompiler::kEagerCompile)
           .ToLocal(&script)) {
    std::fprintf(stderr, "test script did not compile\n");
    return 1;
  }
  std::unique_ptr<v8::ScriptCompiler::CachedData> cache(
      v8::ScriptCompiler::CreateCodeCache(script));
  std::ofstream out(out_path, std::ios::binary);
  out.write(reinterpret_cast<const char*>(cache->data), cache->length);
  std::printf("wrote %d bytes to %s\n", cache->length, out_path);
  return out ? 0 : 1;
}

static int Disassemble(v8::Isolate* isolate, const char* in_path) {
  std::ifstream in(in_path, std::ios::binary);
  if (!in) {
    std::fprintf(stderr, "cannot open %s\n", in_path);
    return 2;
  }
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(in)),
                            std::istreambuf_iterator<char>());
  if (data.empty()) {
    std::fprintf(stderr, "%s is empty\n", in_path);
    return 2;
  }

  auto* cached = new v8::ScriptCompiler::CachedData(
      data.data(), static_cast<int>(data.size()));
  v8::ScriptOrigin origin(v8::String::NewFromUtf8Literal(isolate, "app.bin"));
  v8::ScriptCompiler::Source source(
      v8::String::NewFromUtf8Literal(isolate, "\"dummy\""), origin, cached);

  v8::MaybeLocal<v8::UnboundScript> script =
      v8::ScriptCompiler::CompileUnboundScript(
          isolate, &source, v8::ScriptCompiler::kConsumeCodeCache);
  (void)script;
  std::cout << std::flush;

  if (cached->rejected) {
    std::fprintf(stderr, "V8 rejected %s (wrong file, or wrong V8 build)\n",
                 in_path);
    return 1;
  }
  return 0;
}

int main(int argc, char* argv[]) {
  bool make_test = argc == 3 && std::string(argv[1]) == "--make-test";
  if (argc != 2 && !make_test) {
    std::fprintf(stderr,
                 "usage: %s app.bin > disasm.txt\n"
                 "       %s --make-test test.bin\n",
                 argv[0], argv[0]);
    return 2;
  }

  v8::V8::SetFlagsFromString("--no-lazy --no-flush-bytecode");
  v8::V8::InitializeICUDefaultLocation(argv[0]);
  v8::V8::InitializeExternalStartupData(argv[0]);
  std::unique_ptr<v8::Platform> platform = v8::platform::NewDefaultPlatform();
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  v8::Isolate::CreateParams params;
  params.array_buffer_allocator =
      v8::ArrayBuffer::Allocator::NewDefaultAllocator();
  v8::Isolate* isolate = v8::Isolate::New(params);

  int rc;
  {
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    v8::Local<v8::Context> context = v8::Context::New(isolate);
    v8::Context::Scope context_scope(context);
    rc = make_test ? MakeTest(isolate, argv[2]) : Disassemble(isolate, argv[1]);
  }

  isolate->Dispose();
  v8::V8::Dispose();
  v8::V8::ShutdownPlatform();
  delete params.array_buffer_allocator;
  return rc;
}
