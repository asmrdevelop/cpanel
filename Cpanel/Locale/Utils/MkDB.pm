package Cpanel::Locale::Utils::MkDB;

# cpanel - Cpanel/Locale/Utils/MkDB.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils         ();
use Cpanel::Debug                 ();
use Cpanel::Locale::Utils::Legacy ();

$Cpanel::Locale::Utils::MkDB::only_non_existant = 0;

sub from_hash {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $save_to, $hr, $force_level, $charset ) = @_;

    my $mtime = 0;

    # this is not used in normal operation, probably only ever CDB compilation so:
    # We don't want this linked to all binaries using this so we require() it
    # We do it here so we don't even have to load it if it isn't used.
    # That savings is probably worth the extra exists() that calling require() multiple times would do
    require Cpanel::YAML::Syck;

    # make Load recognize various implicit types in YAML, such as unquoted true, false,
    # as well as integers and floating-point numbers. Otherwise, only ~ is recognized
    # to be undef.
    $YAML::Syck::ImplicitTyping = 0;

    if ( $force_level == 2 && -e $save_to ) {
        unlink $save_to or return ( 0, translatable("Could not unlink “[_1]”: [_2]"), $save_to, $! );
    }
    else {
        if ( -e $save_to ) {
            my %test;
            my $tie = Cpanel::Locale::Utils::get_readonly_tie( $save_to, \%test );

            my $corrupt = $tie ? 0 : 1;

            undef $tie;
            untie %test;

            if ($corrupt) {
                Cpanel::Debug::log_info("Detected corrupt CDB file, removing so that it can be rebuilt ...");
                unlink $save_to or return ( 0, translatable("Could not unlink “[_1]”: [_2]"), $save_to, $! );
            }
        }

        $mtime = 1;
    }

    if ( !$force_level ) {

        my $changed = -e $save_to ? 0 : 1;

        my %read;
        my $rtie;
        if ( !$changed ) {
            $rtie = Cpanel::Locale::Utils::get_readonly_tie( $save_to, \%read ) || $changed++;

            if ( !$changed && exists $hr->{'__VERSION'} && exists $read{'__VERSION'} && $read{'__VERSION'} ne $hr->{'__VERSION'} ) {
                $changed++;
            }
            elsif ( !$changed && exists $read{'__FORENSIC'} ) {
                my $cur_struct = YAML::Syck::Load( $read{'__FORENSIC'} );
                my $cur_len    = exists $cur_struct->{'order'}       && int scalar( ref( $cur_struct->{'order'} ) eq 'ARRAY'       ? @{ $cur_struct->{'order'} }       : () );
                my $new_len    = exists $hr->{'__FORENSIC'}{'order'} && int scalar( ref( $hr->{'__FORENSIC'}{'order'} ) eq 'ARRAY' ? @{ $hr->{'__FORENSIC'}{'order'} } : () );

                if ( $cur_len == $new_len ) {
                    for my $idx ( 0 .. $cur_len - 1 ) {
                        if ( $cur_struct->{'order'}[$idx] ne $hr->{'__FORENSIC'}{'order'}[$idx] ) {
                            $changed++;
                            last;
                        }
                        if ( $cur_struct->{'mtime'}{ $cur_struct->{'order'}[$idx] } ne $hr->{'__FORENSIC'}{'mtime'}{ $hr->{'__FORENSIC'}{'order'}[$idx] } ) {
                            $changed++;
                            last;
                        }
                    }
                }
                else {
                    $changed++;
                }
            }
        }

        if ( !$changed ) {
            undef $rtie;
            untie %read;
            return ( 1, translatable("CDB file “[_1]” is already current"), $save_to );
        }

        undef $rtie;
        untie %read;
    }

    # this should avoid any 'same-second' updates from erroneously returning false
    if ($mtime) {
        $mtime = ( stat($save_to) )[9] || 6;
        $mtime -= 5;
        utime( $mtime, $mtime, $save_to );    # ? update touchfile() to take an arg to specify desired a/mtime ?
    }

    my $build_attempt = 1;

  BUILD:
    my %new;

    my $legacy_lookup = Cpanel::Locale::Utils::Legacy::fetch_legacy_lookup();

    while ( my ( $k, $v ) = each %{$hr} ) {
        if ( $k eq 'charset' ) {
            next;
        }
        elsif ( $k eq '__FORENSIC' ) {
            $new{$k} = YAML::Syck::Dump($v);
            next;
        }
        elsif ( defined $charset ) {
            my $new_k = $k;
            my $new_v = $v;

            require Encode;
            $new_k = Encode::decode( $charset, $new_k );
            $new_v = Encode::decode( $charset, $new_v );
            $new_k = Encode::encode( 'utf-8', $new_k );
            $new_v = Encode::encode( 'utf-8', $new_v );

            if ( !$Cpanel::Locale::Utils::MkDB::only_non_existant || !exists $new{$new_k} ) {
                $new{$new_k} = $new_v;    # mtime is updated, even if the key or value is not new
            }

            if ( !defined $new{$new_k} || $new{$new_k} eq '' ) {
                $new{$new_k} = $new_k;    # hash is one-sided so fallback to the key itself
            }
        }
        else {
            if ( !$Cpanel::Locale::Utils::MkDB::only_non_existant || !exists $new{$k} ) {
                $new{$k} = $v;            # mtime is updated, even if the key or value is not new
            }

            if ( !defined $new{$k} || $new{$k} eq '' ) {
                $new{$k} = $k;            # hash is one-sided so fallback to the key itself
            }
        }

        if ( exists $legacy_lookup->{$k} && $new{$k} =~ tr{'"}{} ) {
            $new{$k} = __make_legacy_quote_safe( $new{$k} );
        }
        elsif ( $new{$k} =~ tr{'"<>&}{} ) {    # has markup chars
            $new{$k} = __make_markup_safe( $new{$k} );
        }
    }

    # each key needs to be done in the while loop or it is incomplete, try rev 37952/37953 vs 37951
    my $create_db_status = Cpanel::Locale::Utils::create_cdb( $save_to, \%new );
    if ( !$create_db_status ) {
        if ( $build_attempt > 2 ) {
            return ( 0, "File not updated “[_1]”: [_2]", $save_to, $! );
        }
        Cpanel::Debug::log_info("Could not get create_cdb on '$save_to' ($!), retrying ...");
        $! = 0;                                ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        sleep($build_attempt);
        $build_attempt++;
        goto BUILD;
    }

    if ( $force_level == 2 ) {
        return ( 1, "File updated “[_1]”", $save_to ) if -s $save_to;
        if ( $build_attempt > 2 ) {
            return ( 0, "File not updated “[_1]”: [_2]", $save_to, $! );
        }
        Cpanel::Debug::log_info("Writeable tie on non-existent '$save_to' ($!) resulted in empty or non-existant file, retrying ...");
        $! = 0;                                ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        sleep($build_attempt);
        $build_attempt++;
        goto BUILD;
    }
    else {

        # w/ create_cdb() mtime is updated when created, new keys or values are given, and if no new keys or values are introduced in an assignment ()
        return ( 1, "File updated “[_1]”", $save_to ) if ( stat($save_to) )[9] > $mtime;
        if ( $build_attempt > 2 ) {
            return ( 0, "File not updated “[_1]”: [_2]", $save_to, $! );
        }
        Cpanel::Debug::log_info("Writeable tie on existing '$save_to' ($!) had no mtime update, retrying ...");
        $! = 0;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        sleep($build_attempt);
        $build_attempt++;
        goto BUILD;
    }
}

sub get_hash_of_legacy_file_or_its_cache {
    my ($legacy_file) = @_;

    require Cpanel::Locale::Utils::Legacy;
    my $legacy_file_cache = Cpanel::Locale::Utils::Legacy::get_legacy_file_cache_path($legacy_file);

    if ( -e $legacy_file_cache ) {

        require 'Cpanel/SafeStorable.pm';    ## no critic qw(Bareword) - hide from perlpkg
        my $hr;
        eval { local $SIG{__DIE__}; local $SIG{__WARN__}; $hr = Cpanel::SafeStorable::retrieve($legacy_file_cache); };

        # warn if !$hr ??
        return $hr || {};
    }
    else {
        return get_hash_of_legacy_file($legacy_file) || {};
    }
}

sub get_hash_of_legacy_file {
    my ($legacy_file) = @_;

    require Cpanel::Config::LoadConfig;

    return scalar Cpanel::Config::LoadConfig::loadConfig( $legacy_file, undef, '=' );
}

# temporary functions copied in that will be replaced by reusable functions in a later PBI
sub __make_markup_safe {
    my ($phrase) = @_;

    # swap markup for BN: (temporary until rt 78989)

    eval { require Cpanel::CPAN::Locale::Maketext::Utils::Phrase; };    # It'd be odd for this to fail other than when compiling a 5.6 binary, hence the error message below
    if ($@) {
        Cpanel::Debug::log_die("from_hash() can not be called in compiled code due to a qr// in a CPAN module that Cpanel::CPAN::Locale::Maketext::Utils::Phrase needs.");
    }

    my $struct = $phrase =~ tr/~[]// ? Cpanel::CPAN::Locale::Maketext::Utils::Phrase::phrase2struct($phrase) : [$phrase];

    my %map = (
        "'" => 39,
        '"' => 34,
        '<' => 60,
        '>' => 62,
        '&' => 38,
    );

    $phrase = '';
    for my $piece ( @{$struct} ) {
        if ( !ref($piece) ) {
            if ( $piece =~ tr/'"<>&// ) {
                $piece =~ s/'/[output,apos]/g;
                $piece =~ s/"/[output,quot]/g;
                $piece =~ s/</[output,lt]/g;
                $piece =~ s/>/[output,gt]/g;
                $piece =~ s/&/[output,amp]/g;
            }
            $phrase .= $piece;
        }
        else {
            $piece->{'cont'} =~ s/(chr[(,])(['"<>&])/$1$map{$2}/g;    # turn all method and embedded ones into numeric
            $piece->{'cont'} =~ s/(['"<>&])/chr\($map{$1}\)/g;        # embed the rest. in the event the method supports embedded methods great, in the event it doesn't at least it won't have markup

            $phrase .= "[$piece->{'cont'}]";
        }
    }

    return $phrase;
}

sub __make_legacy_quote_safe {
    my ($phrase) = @_;

    # We don’t worry about chr() inside BN like __make_markup_safe() since legacy
    # values don’t contain any applicable bracket notation and no new values should be added.

    if ( index( $phrase, q{"} ) > -1 ) {

        # swap every Q but =Q
        $phrase =~ s{(?<!.=)"}{[output,quot]}g if index( $phrase, q{"} ) > -1;

        # turn any =Q…[output,…] back into =Q…Q
        $phrase =~ s{(.="[^"]*?)\[output,quot\]}{$1"}g if index( $phrase, q{"} ) > -1;
    }

    if ( index( $phrase, q{'} ) > -1 ) {

        # swap every Q but =Q
        $phrase =~ s{(?<!.=)'}{[output,apos]}g;

        # turn any =Q…[output,…] back into =Q…Q
        $phrase =~ s{(.='[^']*?)\[output,apos\]}{$1'}g;

        # the only ' left should be attribute quotes, so make them "
        # so that "-in-HTML-attr is all we have to worry about caller-wise (just like BN HTML output)
        $phrase =~ tr{'}{"};
    }

    # Do we want this?
    # if ( $phrase =~ tr/<// != $phrase =~ tr/>// ) {
    #    warn "Unbalanced angle brackets in legacy value ($phrase)\n";
    # }

    return $phrase;
}

sub translatable {    ## no extract maketext
    return $_[0];
}

1;
