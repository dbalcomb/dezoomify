dezoomify
=========

## Installation

Install graphicsmagick:

    brew install graphicsmagick

Then install via git:

    npm install -g git://github.com/dbalcomb/dezoomify.git

## Example

command:

    dezoomify file ~/Desktop/input.csv -b http://www.moma.org/collection_images/zoomifyImages/ -o ~/Workspace/MoMA/dezoomify --skip

input.csv: (input,output)

    ByCRI_p24/cri_324/,cri_0000324.jpg
    ByCRI_p30/cri_1330/,cri_0001330.jpg
    ByCRI_p48/cri_11048/,cri_0011048.jpg

`file` - Read input csv
`--skip` - Skips over files that already exist in the output
`-b` - Base URL for files in input
`-o` - Base directory for output files