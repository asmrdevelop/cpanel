package Cpanel::Locale::Utils::Tool::Phrase;

# cpanel - Cpanel/Locale/Utils/Tool/Phrase.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel ();
use Cpanel::Locale::Utils::Queue                          ();
use Cpanel::CPAN::Locales                                 ();

use Cpanel::Locale ();
use Cpanel::Locale::Utils::Tool;    # indent(), style()
use Cpanel::Locale::Utils::Tool::Find ();

sub subcmd {
    my ( $app, $phrase, @arbitrary_arguments ) = @_;

    die "'phrase' requires a phrase as its first argument." if !defined $phrase || $phrase eq '' || $phrase =~ m/^\-\-/;

    my @phrase_args;
    my $opts = {};

    for my $arg (@arbitrary_arguments) {
        if ( $arg =~ m/^\-\-/ ) {
            my $dashless = $arg;
            $dashless =~ s/^--//;
            die "'phrase' does not know about '$arg'" if $dashless !~ m{^(?:extra-filters|verbose|locale(?:=.*)?)$};
            if ( $dashless =~ m/^locale/ ) {
                if ( $dashless =~ m/^locale=(\S+)$/ ) {
                    $opts->{'locale'} = Cpanel::CPAN::Locales::normalize_tag("$1");    # "$1" helps avoid potential oddness when passing $1 to a function that might alter $1
                }
                else {
                    die "You must define the locale with --locale={locale_tag}";
                }
            }
            else {
                $opts->{$dashless} = 1;
            }
        }
        else {
            push @phrase_args, $arg;
        }
    }

    run( $phrase, $opts, @phrase_args );
    return;
}

sub run {
    my ( $phrase, $opts, @phrase_args ) = @_;

    my $loc = Cpanel::Locale->get_handle( $opts->{'locale'} );

    if ( $opts->{'locale'} ) {
        print "Locale: $opts->{'locale'} (" . $loc->get_locale_name( $opts->{'locale'} ) . ")\n";
    }

    print "Object: " . $loc->get_language_tag() . ' (' . $loc->get_locale_name() . ")\n";
    print "Phrase: " . style( "highlight", $phrase ) . "\n";

    # Render:
    print indent() . style( 'bold', "Rendered:" ) . "\n";
    print indent(2) . style( "info", "ANSI" ) . " : " . $loc->maketext_ansi_context( $phrase, @phrase_args ) . "\n";     ## no extract maketext
    print indent(2) . style( "info", "HTML" ) . " : " . $loc->maketext_html_context( $phrase, @phrase_args ) . "\n";     ## no extract maketext
    print indent(2) . style( "info", "Plain" ) . ": " . $loc->maketext_plain_context( $phrase, @phrase_args ) . "\n";    ## no extract maketext

    # Status:
    my $location = Cpanel::Locale::Utils::Queue::get_location_of_key( 'en', $phrase );
    if ( $location eq 'lexicon' ) {
        print indent() . "Status:  " . style( "info", "In official lexicon" ) . "\n";
    }
    elsif ( $location eq 'queue' ) {
        print indent() . "Status:  " . style( "info", "Queued for translation" ) . "\n";
    }
    elsif ( $location eq 'human' ) {
        print indent() . "Status:  " . style( "info", "Has human translation" ) . "\n";
    }
    elsif ( $location eq 'machine' ) {
        print indent() . "Status:  " . style( "info", "Has machine translation" ) . "\n";
    }
    else {
        print indent() . "Status:  " . style( "info", "New (not in main cPanel repo)" ) . "\n";
    }

    # Checker:
    my $norm = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel->new_source( { 'run_extra_filters' => $opts->{'extra-filters'} } ) || die "Could not create normalization object";

    my $res = $norm->normalize($phrase);

    if ( $res->get_violation_count() ) {
        print indent() . "Checker:  " . style( 'error', 'Failed' ) . "\n";
    }
    elsif ( $res->get_warning_count() ) {
        print indent() . "Checker:  " . style( 'warn', 'Has Warnings' ) . "\n";
    }
    else {
        print indent() . "Checker:  " . style( 'good', 'Passed' ) . "\n";
    }

    # We probably should do a more public friendly version of _walk_filter()
    Cpanel::Locale::Utils::Tool::Find::_walk_filter( $res, 0, 2, $opts );           # 2nd arg: 0 means warning, 3rd arg is initial indent() number
    return Cpanel::Locale::Utils::Tool::Find::_walk_filter( $res, 1, 2, $opts );    # 2nd arg: 1 means violations, 3rd arg is initial indent() number
}

1;
