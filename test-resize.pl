#!/usr/bin/env perl
use strict;
use warnings;

use Image::Magick;

my $image = Image::Magick->new;

open my $fh, '<', 'images/jpg/american_robin.jpg';
$image->Read( file => $fh );
close $fh;

$image->Resize( geometry => '200x' );
open my $ofh, '>', 'images/american_robin.png';
$image->Write( file => $ofh, filename => 'images/american_robin.png' );
close $ofh;

1;
