NPMJS = "NPMJS"
GERRIT = "GERRIT"

NPM_VERSIONS = {
  "bower":   '1.7.9',
  'crisper': '2.0.2',
  'vulcanize': '1.14.8',
}

NPM_SHA1S = {
  "bower":  'b7296c2393e0d75edaa6ca39648132dd255812b0',
  "crisper": '7183c58cea33632fb036c91cefd1b43e390d22a2',
  'vulcanize': '679107f251c19ab7539529b1e3fdd40829e6fc63',
}


def _npm_tarball(name):
  return "%s@%s.npm_binary.tgz" % (name, NPM_VERSIONS[name])


def _npm_binary_impl(ctx):
  """rule to download a NPM archive."""
  name = ctx.name
  version= NPM_VERSIONS[name]
  sha1 = NPM_VERSIONS[name]

  dir = '%s-%s' % (name, version)
  filename = '%s.tgz' % dir
  base =  '%s@%s.npm_binary.tgz' % (name, version)
  dest = ctx.path(base)
  repository = ctx.attr.repository
  if repository == GERRIT:
    url = 'http://gerrit-maven.storage.googleapis.com/npm-packages/%s' % filename
  elif repository == NPMJS:
    url = 'http://registry.npmjs.org/%s/-/%s' % (name, filename)
  else:
    fail('repository %s not in {%s,%s}' % (repository, GERRIT, NPMJS))

  python = ctx.which("python")
  script = ctx.path(ctx.attr._download_script)

  sha1 = NPM_SHA1S[name]
  args = [python, script, "-o", dest, "-u", url, "-v", sha1]
  out = ctx.execute(args)
  if out.return_code:
    fail("failed %s: %s" % (args, out.stderr))
  ctx.file("BUILD", "package(default_visibility=['//visibility:public'])\nfilegroup(name='tarball', srcs=['%s'])" % base, False)

npm_binary = repository_rule(
    implementation=_npm_binary_impl,
    local=True,
    attrs={
      # Label resolves within repo of the .bzl file.
      "_download_script": attr.label(default=Label("//tools:download_file.py")),
      "repository": attr.string(default=NPMJS),
    })


# for use in repo rules.
def _run_npm_binary_str(ctx, tarball, args):
  python_bin = ctx.which("python")
  return " ".join([
    python_bin,
    ctx.path(ctx.attr._run_npm),
    ctx.path(tarball)] + args)


def _bower_archive(ctx):
  """Download a bower package."""
  download_name = '%s__download_bower.zip' % ctx.name
  renamed_name = '%s__renamed.zip' % ctx.name
  version_name = '%s__version.json' % ctx.name

  cmd = [
      ctx.which("python"),
      ctx.path(ctx.attr._download_bower),
      '-b', '%s' % _run_npm_binary_str(ctx, ctx.attr._bower_archive, []),
      '-n', ctx.name,
      '-p', ctx.attr.package,
      '-v', ctx.attr.version,
      '-s', ctx.attr.sha1,
      '-o', download_name,
    ]

  out = ctx.execute(cmd)
  if out.return_code:
    fail("failed %s: %s" % (" ".join(cmd), out.stderr))

  _bash(ctx, " && " .join([
    "TMP=$(mktemp -d )",
    "cd $TMP",
    "mkdir bower_components",
    "cd bower_components",
    "unzip %s" % ctx.path(download_name),
    "cd ..",
    "zip -r %s bower_components" % renamed_name,]))

  dep_version = ctx.attr.semver if ctx.attr.semver else ctx.attr.version
  ctx.file(version_name,
           '"%s":"%s#%s"' % (ctx.name, ctx.attr.package, dep_version))
  ctx.file(
    "BUILD",
    "\n".join([
      "package(default_visibility=['//visibility:public'])",
      "filegroup(name = 'zipfile', srcs = ['%s'], )" % download_name,
      "filegroup(name = 'version_json', srcs = ['%s'], visibility=['//visibility:public'])" % version_name,
    ]), False)


def _bash(ctx, cmd):
  cmd_list = ["/bin/bash", "-c", cmd]
  out = ctx.execute(cmd_list)
  if out.return_code:
    fail("failed %s: %s", cmd_list, out.stderr)


bower_archive=repository_rule(
  _bower_archive,
  attrs={
    "_bower_archive": attr.label(default=Label("@bower//:%s" % _npm_tarball("bower"))),
    "_run_npm": attr.label(default=Label("//tools/js:run_npm_binary.py")),
    "_download_bower": attr.label(default=Label("//tools/js:download_bower.py")),
    "sha1": attr.string(mandatory=True),
    "version": attr.string(mandatory=True),
    "package": attr.string(mandatory=True),
    "semver": attr.string(),
  })


def _bower_component_impl(ctx):
  transitive_zipfiles = set([ctx.file.zipfile])
  for d in ctx.attr.deps:
    transitive_zipfiles += d.transitive_zipfiles

  transitive_licenses = set()
  if ctx.file.license:
    transitive_licenses += set([ctx.file.license])

  for d in ctx.attr.deps:
    transitive_licenses += d.transitive_licenses

  transitive_versions = set(ctx.files.version_json)
  for d in ctx.attr.deps:
    transitive_versions += d.transitive_versions

  return struct(
    transitive_zipfiles=transitive_zipfiles,
    transitive_versions=transitive_versions,
    transitive_licenses=transitive_licenses,
  )


_common_attrs = {
    "deps": attr.label_list(providers=[
      "transitive_zipfiles",
      "transitive_versions",
      "transitive_licenses",
    ])
  }


def _js_component(ctx):
  dir = ctx.outputs.zip.path + ".dir"
  name = ctx.outputs.zip.basename
  if name.endswith(".zip"):
    name = name[:-4]
  dest = "%s/%s" % (dir, name)
  cmd = " && ".join([
    "mkdir -p %s" % dest,
    "cp %s %s/" % (' '.join([s.path for s in ctx.files.srcs]), dest),
    "cd %s" % dir,
    "find . -exec touch -t 198001010000 '{}' ';'",
    "zip -qr ../%s *" %  ctx.outputs.zip.basename
  ])

  ctx.action(
    inputs = ctx.files.srcs,
    outputs = [ctx.outputs.zip],
    command = cmd,
    mnemonic = "GenBowerZip")

  licenses = set()
  if ctx.file.license:
    licenses += set([ctx.file.license])

  return struct(
    transitive_zipfiles=list([ctx.outputs.zip]),
    transitive_versions=set([]),
    transitive_licenses=licenses)


js_component = rule(
  _js_component,
  attrs=_common_attrs + {
    "srcs": attr.label_list(allow_files=[".js"]),
    "license": attr.label(allow_single_file=True),
  },
  outputs={
    "zip": "%{name}.zip",
  }
)


_bower_component = rule(
  _bower_component_impl,
  attrs=_common_attrs + {
    "zipfile": attr.label(allow_single_file=[".zip"]),
    "license": attr.label(allow_single_file=True),
    "version_json": attr.label(allow_files=[".json"]),

    # If set, define by hand, and don't regenerate this entry in bower2bazel.
    "seed": attr.bool(default=False)
  })



# TODO(hanwen): make license mandatory.
def bower_component(name, license=None, **kwargs):
  prefix = "//lib:LICENSE-"
  if license and not license.startswith(prefix):
    license = prefix + license
  _bower_component(
    name=name,
    license=license,
    zipfile="@%s//:zipfile"% name,
    version_json="@%s//:version_json" % name,
    **kwargs)


def _bower_component_bundle_impl(ctx):
  """A bunch of bower components zipped up."""
  zips = set([])
  for d in ctx.attr.deps:
    zips += d.transitive_zipfiles

  versions = set([])
  for d in ctx.attr.deps:
    versions += d.transitive_versions

  licenses = set([])
  for d in ctx.attr.deps:
    licenses += d.transitive_versions

  out_zip = ctx.outputs.zip
  out_versions = ctx.outputs.version_json

  ctx.action(
    inputs=list(zips),
    outputs=[out_zip],
    command=" && ".join([
      "p=$PWD",
      "rm -rf %s.dir" % out_zip.path,
      "mkdir -p %s.dir/bower_components" % out_zip.path,
      "cd %s.dir/bower_components" % out_zip.path,
      "for z in %s; do unzip -q $p/$z ; done" % " ".join(sorted([z.path for z in zips])),
      "cd ..",
      "find . -exec touch -t 198001010000 '{}' ';'",
      "zip -qr $p/%s bower_components/*" % out_zip.path,
    ]),
    mnemonic="BowerCombine")

  ctx.action(
    inputs=list(versions),
    outputs=[out_versions],
    mnemonic="BowerVersions",
    command="(echo '{' ; for j in  %s ; do cat $j; echo ',' ; done ; echo \\\"\\\":\\\"\\\"; echo '}') > %s" % (" ".join([v.path for v in versions]), out_versions.path))

  return struct(
    transitive_zipfiles=zips,
    transitive_versions=versions,
    transitive_licenses=licenses)


bower_component_bundle = rule(
  _bower_component_bundle_impl,
  attrs=_common_attrs,
  outputs={
    "zip": "%{name}.zip",
    "version_json": "%{name}-versions.json",
  }
)

def _vulcanize_impl(ctx):
  # intermediate artifact.
  vulcanized = ctx.new_file(
    ctx.configuration.genfiles_dir, ctx.outputs.html, ".vulcanized.html")
  destdir = ctx.outputs.html.path + ".dir"
  zips =  [z for d in ctx.attr.deps for z in d.transitive_zipfiles ]

  hermetic_npm_binary = " ".join([
    'python',
    "$p/" + ctx.file._run_npm.path,
    "$p/" + ctx.file._vulcanize_archive.path,
    '--inline-scripts',
    '--inline-css',
    '--strip-comments',
    '--out-html', "$p/" + vulcanized.path,
    ctx.file.app.path
  ])

  pkg_dir = ctx.attr.pkg.lstrip("/")
  cmd = " && ".join([
    # unpack dependencies.
    "export PATH",
    "p=$PWD",
    "rm -rf %s" % destdir,
    "mkdir -p %s/%s/bower_components" % (destdir, pkg_dir),
    "for z in %s; do unzip -qd %s/%s/bower_components/ $z; done" % (
      ' '.join([z.path for z in zips]), destdir, pkg_dir),
    "tar -cf - %s | tar -C %s -xf -" % (" ".join([s.path for s in ctx.files.srcs]), destdir),
    "cd %s" % destdir,
    hermetic_npm_binary,
  ])
  ctx.action(
    mnemonic = "Vulcanize",
    inputs = [ctx.file._run_npm, ctx.file.app,
              ctx.file._vulcanize_archive
    ] + list(zips) + ctx.files.srcs,
    outputs = [vulcanized],
    command = cmd)

  hermetic_npm_command = "export PATH && " + " ".join([
    'python',
    ctx.file._run_npm.path,
    ctx.file._crisper_archive.path,
    "--always-write-script",
    "--source", vulcanized.path,
    "--html", ctx.outputs.html.path,
    "--js", ctx.outputs.js.path])

  ctx.action(
    mnemonic = "Crisper",
    inputs = [ctx.file._run_npm, ctx.file.app,
              ctx.file._crisper_archive, vulcanized],
    outputs = [ctx.outputs.js, ctx.outputs.html],
    command = hermetic_npm_command)


_vulcanize_rule = rule(
  _vulcanize_impl,
  attrs = {
    "deps": attr.label_list(providers=["transitive_zipfiles"]),
    "app": attr.label(mandatory=True, allow_single_file=True),
    "srcs": attr.label_list(allow_files=[".js", ".html", ".txt", ".css", ".ico"]),

    "pkg": attr.string(mandatory=True),
    "_run_npm": attr.label(
      default=Label("//tools/js:run_npm_binary.py"),
      allow_single_file=True
    ),
    "_vulcanize_archive": attr.label(
      default=Label("@vulcanize//:%s" % _npm_tarball("vulcanize")),
      allow_single_file=True
    ),
    "_crisper_archive": attr.label(
      default=Label("@crisper//:%s" % _npm_tarball("crisper")),
      allow_single_file=True
    ),
  },
  outputs = {
    "html": "%{name}.html",
    "js": "%{name}.js",
  }
)

def vulcanize(*args, **kwargs):
  """Vulcanize runs vulcanize and crisper on a set of sources."""
  _vulcanize_rule(*args, pkg=PACKAGE_NAME, **kwargs)
