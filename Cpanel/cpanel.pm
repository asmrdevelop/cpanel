package Cpanel::cpanel;

# cpanel - Cpanel/cpanel.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## extractions from cpanel.pl

use strict;
use warnings;

use Cpanel                    ();
use Cpanel::Encoder::Tiny     ();
use Cpanel::LoadFile          ();
use Cpanel::Locale            ();
use Cpanel::Debug             ();
use Cpanel::StringFunc::Match ();
use Cpanel::Version           ();
use Cwd                       ();

#[% IF CPANEL.feature('version-11.31.0') -%]
#[% IF CPANEL.feature('mime') -%]
## extracted from cpanel.pl's execfeaturetag
sub check_feature {
    Cpanel::Debug::log_deprecated("This call is deprecated. Use Cpanel::hasfeature instead.");
    my $task = $_[0];
    if ( $task =~ tr/-// && $task =~ /^version-(\S+)/ ) {
        return _version_check( $1, Cpanel::Version::getversionnumber() );
    }
    else {
        #ok to destroy the $task variable since we are about to return
        $task =~ tr/[a-z]/[A-Z]/;
        return $Cpanel::rootlogin
          ? ( ( $task eq 'STYLE' || $task eq 'SETLANG' )                                                   ? 1 : 0 )
          : ( length $Cpanel::CPDATA{ 'FEATURE-' . $task } && $Cpanel::CPDATA{ 'FEATURE-' . $task } eq '0' ? 0 : 1 );
    }
}

sub _version_check {
    my ( $arg, $installed ) = @_;
    my @arg       = split( /\./, $arg );
    my @installed = split( /\./, $installed );

    if ( $arg[0] == $installed[0] ) {
        if ( $arg[1] == $installed[1] ) {
            return $arg[2] <= $installed[2];
        }
        return $arg[1] <= $installed[1];
    }
    return $arg[0] <= $installed[0];
}

## stolen from cpanel.pl and reduced; used in stdfooter.tt
sub _print_help {
    return _get_relative_include( $Cpanel::Parser::Vars::firstfile, 'help' );
}

## stolen from cpanel.pl
sub is_readable_and_nonzero_file {
    return -f $_[0] && -r _ && -s _;
}

## stolen and mildly changed from cpanel.pl; if more is needed, also check cpanel.pl's
##   '''if ( $module eq 'printhelp' )''' block
sub _get_relative_include {
    my ( $file, $dir ) = @_;
    return if !$dir || !$file;

    my $bbasedir        = ( ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend' );
    my $token_prefix    = 'cpsess';
    my $token_strip_end = '___';
    $file =~ s!^/?\Q${token_prefix}\E\d*(?:/|$token_strip_end)?!/!g;
    $file =~ s!^\.?/?!!g;
    $file =~ s/[.][.]//g;
    $file =~ s!$bbasedir/([^/]+)!./$bbasedir/$1/$dir!;
    $file =~ s!/\./!/!g;
    $file =~ tr{/}{}s;                                                 # collapse //s to /

    if ( $file =~ m!^\./! ) {
        my $cwd = Cwd::fastcwd();
        $file =~ s/^\./$cwd/g;
    }

    if (   !Cpanel::StringFunc::Match::beginmatch( $file, '/usr/local/cpanel/base/frontend/' )
        && !Cpanel::StringFunc::Match::beginmatch( $file, '/usr/local/cpanel/base/webmail/' ) ) {
        return 'Sorry, ' . Cpanel::Encoder::Tiny::safe_html_encode_str($file) . ' is not permitted to be included.';
    }

    my $tag = Cpanel::Locale->get_handle()->get_language_tag();

    ## cpdev: will resolve to x3/help/$etc, or uncomment the below to force x3/.locale.help/es/$etc
    #$tag = 'es';

    my $localized = $file;
    $localized =~ s!/help/!/.locale.help/$tag/!;

    my $include_fname;
    if ( $dir eq 'help' && $localized ne $file && is_readable_and_nonzero_file($localized) ) {
        $include_fname = $localized;
    }
    elsif ( $dir eq 'help' && $file !~ /\.html$/ && $localized ne $file && is_readable_and_nonzero_file( $localized . '.html' ) ) {
        $include_fname = $localized . '.html';
    }
    elsif ( is_readable_and_nonzero_file($file) ) {
        $include_fname = $file;
    }
    elsif ( $file !~ /\.html$/ && is_readable_and_nonzero_file( $file . '.html' ) ) {
        $include_fname = $file . '.html';
    }
    elsif ( $file !~ /\.tt$/ && is_readable_and_nonzero_file( $file . '.tt' ) ) {
        $include_fname = $file . '.tt';
    }
    elsif ( $dir eq 'help' ) {
        my $no_help_file           = "/usr/local/cpanel/base/$bbasedir/" . $Cpanel::CPDATA{'RS'} . '/help/nohelp.html';
        my $localized_no_help_file = $no_help_file;
        $localized_no_help_file =~ s!/help/!/.locale.help/$tag/!;
        if ( -f $localized_no_help_file && -r _ && -s _ ) {
            $include_fname = $localized_no_help_file;
        }
        elsif ( -f $no_help_file && -r _ && -s _ ) {
            $include_fname = $no_help_file;
        }
    }

    ## case 59243: the 'help' files are loaded in raw mode; no variable interpolation
    return eval { Cpanel::LoadFile::loadfile($include_fname) };    # silently ignore errors [preserve original behavior]
}

##################################################
## the hash and the two subroutines need to be removed, but this currently breaks index.html;
##   need to divorce the .uapi multi-plexing
my %_includes = (
    dynamic => 1,
    rel     => 2,
    relraw  => 3,
    raw     => 4
);

## note: this is called by Cpanel/API/Branding, but only when the URL is a .html file;
##   !do not call this from a .tt URL (meaning, uapi.pl), because there is no
##   &main::doinclude!
sub _wrap_include {
    my ( $include_file, @opts ) = @_;
    if ( defined $opts[0] && exists $_includes{ $opts[0] } ) {
        $opts[0] = $_includes{ $opts[0] };
    }

    require Cpanel::FHTrap;
    my $fhtrap = Cpanel::FHTrap->new();
    local $@;
    ## note: presupposes running in cpanel.pl as the main package
    eval { main::doinclude( $include_file, @opts ); 1; };
    if ($@) {
        warn $@;
    }

    return $fhtrap->close();
}

1;
