#!/usr/bin/env perl
# -*- mode: cperl; -*-

package BirdBot;

use strict;
use warnings;

use Carp;
use CLI::Simple;
use CLI::Simple::Constants qw(:booleans :chars %LOG_LEVELS);
use Data::Dumper;
use English qw(_no_match_vars);
use File::Basename qw(basename fileparse);
use File::Path qw(make_path);
use JSON;
use Image::Magick;
use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;
use LWP::UserAgent;
use List::Util qw(pairs uniq);
use URI::Escape;

use Readonly;
Readonly::Scalar our $SEARCH_URL => 'https://commons.wikimedia.org/w/api.php';

use parent qw(CLI::Simple);

########################################################################
sub resize {
########################################################################
  my ( $self, %args ) = @_;

  my ( $file, $width, $height ) = @args{qw(file width height)};

  my $out_dir //= $self->get_img_dir;

  croak sprintf 'ERROR: image directory not found!'
    if !$out_dir || !-d $out_dir;

  croak sprintf 'ERROR: no such file (%s) found!', $file
    if !-s $file;

  $width  //= '200';
  $height //= $EMPTY;
  my $geometry = sprintf '%sx%s', $width, $height;

  my ( $name, $path, $ext ) = fileparse $file, qr/[.][^.]+$/xsm;

  my $image = Image::Magick->new;

  open my $fh, '<', $file;
  $image->Read( file => $fh );
  close $fh;

  my $outfile = sprintf '%s/%s.png', $out_dir, $name;

  $image->Resize( geometry => $geometry );
  open my $ofh, '>', $outfile;
  $image->Write( file => $ofh, filename => $outfile );
  close $ofh;

  return $outfile;
}

########################################################################
sub fetch_image {
########################################################################
  my ( $self, $image_url, $filename ) = @_;

  my $img = $self->get_ua->get($image_url);

  return if !$img->is_success;

  save_image( $filename => $img->decoded_content );

  return $img->is_success;
}

########################################################################
sub find_bird {
########################################################################
  my ( $self, $bird ) = @_;

  my $ua = $self->get_ua;

  my %search_args = (
    action      => 'query',
    format      => 'json',
    list        => 'search',
    srsearch    => "intitle:$bird",
    srnamespace => 6,
    srlimit     => 1,
  );

  my $search_url = format_query_string( $SEARCH_URL, %search_args );

  return $ua->get($search_url);
}

########################################################################
sub get_image_url {
########################################################################
  my ( $self, $hit, $bird ) = @_;

  my $ua = $self->get_ua;

  my $info_url = format_query_string(
    'https://commons.wikimedia.org/w/api.php',
    action => 'query',
    format => 'json',
    titles => $hit,
    prop   => 'imageinfo',
    iiprop => 'url'
  );

  my $info_res = $ua->get($info_url);

  return
    if !$info_res->is_success;

  my $info_data = decode_json( $info_res->decoded_content );

  my ($page) = values %{ $info_data->{query}{pages} // {} };

  my $image_url = $page->{imageinfo}[0]{url};

  if ( !$image_url ) {
    DEBUG sprintf 'Image URL not found for %s (%s)', $bird, $hit;
  }

  return $image_url;
}

########################################################################
sub save_image {
########################################################################
  my ( $filename, $image ) = @_;

  if ( open my $fh, '>', $filename ) {
    binmode $fh;
    print {$fh} $image;
    close $fh;
  }
  else {
    warn "Cannot save $filename: $OS_ERROR\n";
  }

  return;
}

########################################################################
sub fix_filename {
########################################################################
  my ($bird) = @_;

  my $filename = lc $bird;
  $filename =~ s/\s+/_/xsmg;
  $filename =~ s/[^\w]//xmsg;

  return $filename;
}

########################################################################
sub format_query_string {
########################################################################
  my ( $base_url, @args ) = @_;
  my @query;

  foreach my $p ( pairs @args ) {
    push @query, sprintf '%s=%s', $p->[0], uri_escape $p->[1];
  }

  return sprintf '%s?%s', $base_url, join q{&}, @query;
}

########################################################################
sub init {
########################################################################
  my ($self) = @_;

  my $log_level = $self->get_log_level || 'info';

  Log::Log4perl->easy_init( $LOG_LEVELS{$log_level} // $LOG_LEVELS{info} );

  make_path( $self->get_out_dir );

  make_path( $self->get_img_dir );

  $self->fetch_bird_list;

  my $ua = LWP::UserAgent->new( agent => 'BirdImageBot/1.0' );

  $self->set_ua($ua);

  return;
}

########################################################################
sub fetch_bird_list {
########################################################################
  my ($self) = @_;

  my $bird_list_file = $self->get_manifest // 'birds.txt';

  INFO sprintf 'Reading bird list...[%s]', $bird_list_file;

  my $bird_list = eval {
    open my $fh, '<', $bird_list_file
      or croak "ERROR: could not open $bird_list_file for reading";

    local $RS = undef;

    my $bird_list = <$fh>;
    close $fh;

    return $bird_list;
  };

  if ( !$bird_list || $EVAL_ERROR ) {
    croak "ERROR: could not read $bird_list_file\n$OS_ERROR";
  }

  my @birds = split /\n/, $bird_list;

  $self->set_bird_list( \@birds );

  return \@birds;
}

########################################################################
sub choose(&) {  ## no critic
########################################################################
  my @result = shift->();

  return wantarray ? @result : $result[0];
}

########################################################################
sub cmd_download {
########################################################################
  my ($self) = @_;

  my @birds = choose {
    return $self->get_bird
      if $self->get_bird;

    return @{ $self->get_bird_list // [] };
  };

  my $num_birds = scalar @birds;

  if ( !$num_birds ) {
    WARN 'Sorry, no birds in list!';
    return 1;
  }

  my $max_birds = $self->get_max_birds;

  INFO sprintf 'Found %d birds in list...attempting to download %d images', $num_birds, $max_birds ? $max_birds : $num_birds;

  my $index = 1;

  my $out_dir = $self->get_out_dir;
  my @bird_map;

  for my $bird (@birds) {
    last if $max_birds && $index > $max_birds;

    my $png_file = sprintf '%s/%s.png', $self->get_img_dir, fix_filename($bird);
    if ( !$self->get_force && -e $png_file ) {
      INFO sprintf 'Skipping %s...already downloaded and resized.', $png_file;
      push @bird_map, $bird;
      $index++;
      next;
    }

    INFO sprintf 'Looking for...[%s] [%d/%d]', $bird, $index++, $max_birds ? $max_birds : $num_birds;

    my $search_res = $self->find_bird($bird);

    if ( !$search_res->is_success ) {
      ERROR sprintf 'ERROR: could not find %s...skipping', $bird;
      next;
    }

    INFO sprintf 'Found %s!', $bird;

    my $search_data = decode_json( $search_res->decoded_content );

    DEBUG Dumper( [ search_data => $search_data ] );

    my $hit = $search_data->{query}{search}[0]{title} or do {
      WARN sprintf 'Sadly no such bird ($%s) found in our search', $bird;
      next;
    };

    INFO 'TWEET!';

    my $image_url = $self->get_image_url( $hit, $bird );

    if ( !$image_url ) {
      WARN sprintf 'Sadly no image found for %s', $bird;
      next;
    }

    INFO sprintf 'TWEET! TWEET!=> [%s]', $image_url;

    my ($ext) = $image_url =~ /[.]([[:alnum:]]+)(?:[?].*)?$/xsm;

    $ext = lc $ext // 'jpg';  # default fallback

    my $filename = sprintf '%s/%s.%s', $out_dir, fix_filename($bird), $ext;

    if ( !$self->fetch_image( $image_url, $filename ) ) {
      WARN sprintf 'Sadly...we failed to download image for %s', $bird;
      WARN sprintf '...try again later.';
      return 1;
    }
    else {
      INFO sprintf 'TWEET! TWEET! TWEET!...downloaded an image for %s', $bird;
      INFO sprintf 'Resizing...%s (%d bytes)', $filename, -s $filename;

      my $png = $self->resize( file => $filename, out_dir => $self->get_img_dir );

      if ( -s $png ) {
        INFO sprintf 'TWEET! TWEET! TWEET! TWEET!...resized %s (%d)  successfully!', $png, -s $png;
        push @bird_map, $bird;
      }
      else {
        ERROR sprintf 'ERROR: resizing...%s', $filename;
      }
    }

    sleep $self->get_sleep_time;
  }

  my $autocomplete_file = $self->get_autocomplete_file;

  DEBUG Dumper(
    [ bird_map          => \@bird_map,
      autocomplete_file => $autocomplete_file,
      overwrite         => $self->get_overwrite,
    ]
  );

  if (@bird_map) {
    if ( -e $autocomplete_file && $self->get_overwrite ) {
      local $RS = undef;

      open my $fh, '<', $autocomplete_file;
      my $old_bird_map = decode_json(<$fh>);
      close $fh;

      my @birds = map { $_->{label} } @{$old_bird_map};
      @bird_map = uniq( @birds, @bird_map );
    }

    if ( !-e $autocomplete_file || $self->get_overwrite ) {
      open my $fh, '>', $autocomplete_file
        or croak sprintf "ERROR: could not open %s for writing\n%s", $autocomplete_file, $OS_ERROR;

      my $idx = 1;

      print {$fh} JSON->new->pretty->encode( [ map { { value => $idx++, label => $_ } } uniq @bird_map ] );

      close $fh;
    }
    else {
      WARN 'WARN: autocomplete file not updated! use --overwrite to force update';
    }
  }

  return 0;
}

########################################################################
sub main {
########################################################################
  my @option_specs = qw(
    help|h
    autocomplete-file|a=s
    bird|b=s
    force|f
    img-dir|i=s
    log-level|l=s
    manifest|M=s
    max-birds|m=i
    out-dir|o=s
    overwrite
    sleep-time=i
    width|w=i
  );

  my %commands = ( default => \&cmd_download );

  my @extra_options = qw(bird_list ua);

  my $cli = BirdBot->new(
    commands        => \%commands,
    option_specs    => \@option_specs,
    extra_options   => \@extra_options,
    default_options => {
      width             => '200',
      out_dir           => 'images/jpg',
      img_dir           => 'images',
      autocomplete_file => 'birds.json',
      sleep_time        => 2,
    },
  );

  return $cli->run;
}

exit main();

1;
