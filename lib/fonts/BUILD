load('//tools/bzl:genrule2.bzl', 'genrule2')

# Source Code Pro. Version 2.010 Roman / 1.030 Italics
# https://github.com/adobe-fonts/source-code-pro/releases/tag/2.010R-ro%2F1.030R-it
filegroup(
  name = 'sourcecodepro',
  srcs = [
    'SourceCodePro-Regular.woff',
    'SourceCodePro-Regular.woff2'
  ],
  data = [ "//lib:LICENSE-OFL1.1" ],
  visibility = ['//visibility:public'],
)

# Open Sans at Revision 53a5266 and converted using a Google woff file
# converter (same one that Google Fonts uses).
# https://github.com/google/fonts/tree/master/apache/opensans
genrule2(
  name = 'opensans',
  cmd = 'zip -rq $@ $(SRCS)',
  srcs = [
    'OpenSans-Bold.woff',
    'OpenSans-Bold.woff2',
    'OpenSans-Regular.woff',
    'OpenSans-Regular.woff2'
  ],
  out = 'opensans.zip',
# TODO(hanwen): license.
#  license = 'Apache2.0',
  visibility = ['//visibility:public'],
)
