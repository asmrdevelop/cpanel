package Cpanel::Parser::FeatureIf;

# cpanel - Cpanel/Parser/FeatureIf.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Cpanel::ExpVar not used in because
# rebuild_sprints does not use it
# or have it but it is only used
# when this module is called from
# uapi.pl or cpanel.pl
#
use Cpanel::Debug  ();
use Cpanel::ExpVar ();
use Cpanel         ();

# DEBUG check is now at compile time for speed
use constant DEBUG => 0;

my $nullif        = 0;
my $nullfeatureif = 0;

sub execiftag {
    return ( $nullif = ( ifresult(@_) ? 0 : 1 ) );
}

sub ifresult {    ## no critic qw(Subroutines::RequireArgUnpacking);
    my ( $task, $expectand, $andstatement ) = ( $_[0], 0, 0 );

    if ( $task =~ tr/\<\> // ) {
        substr( $task, -1, 1, '' ) if substr( $task, -1 ) eq '>';
        $task =~ s/[\r\n\t ]+$//          if substr( $task, -1 ) =~ tr{\r\n\t }{};
        $task =~ s/^[\r\n\t ]+//          if substr( $task, -1 ) =~ tr{\r\n\t }{};
        $task =~ s/<+cpanelif[\r\n\t ]*// if index( $task, '<' ) > -1;
    }
    if (DEBUG) {
        Cpanel::Debug::log_info("Processing If Tag: ($task)");
    }
    if ( defined $task && $task =~ tr/ // ) {
        my $nullif = 0;
        foreach $task ( split( /\s+/, $task ) ) {
            if (DEBUG) {
                Cpanel::Debug::log_info("Process: $task");
            }
            if ( $task eq '&&' || $task eq 'and' ) {
                if ( $nullif == 1 ) {
                    if (DEBUG) {
                        Cpanel::Debug::log_info("and conditional and previous condition not met.  Stopped Processing.");
                    }
                    last;
                }
                ( $expectand, $andstatement ) = ( 0, 1 );
                next;
            }

            if ($expectand) {
                if (DEBUG) {
                    Cpanel::Debug::log_info("expecting and conditional one was not given since previous condition already met.  Stopped Processing.");
                }
                last;
            }    #we kept going and it wasn't a and and one condition did match so its an or and we know we got it, so bail.

            $expectand = 0;

            if ( $task eq '||' || $task eq 'or' ) { next(); }

            if (DEBUG) {
                Cpanel::Debug::log_info("Final Pre Expansion Result: $task.");
            }
            if ( !Cpanel::ExpVar::expvar($task) ) {
                $nullif = 1;    #turn if off (do not display)
                if ($andstatement) {
                    if (DEBUG) {
                        Cpanel::Debug::log_info("CpanelIf Result  (0 = show, 1 = skip): $nullif");
                    }
                    return $nullif ? 0 : 1;
                }
            }
            else {
                ( $nullif, $expectand ) = ( 0, 1 );    #turn if on (display)
                                                       #keep going because the next might be a && or an and.
            }

            $andstatement = 0;
        }
        if (DEBUG) {
            Cpanel::Debug::log_info("CpanelIf Result (0 = show, 1 = skip): $nullif");
        }
        return $nullif ? 0 : 1;
    }
    return Cpanel::ExpVar::expvar($task) ? 1 : 0;
}

sub execfeaturetag {
    return ( $nullfeatureif = ( featureresult(@_) ? 0 : 1 ) );
}

sub featureresult {    ## no critic qw(RequireArgUnpacking Subroutines::ProhibitExcessComplexity)
    my $reverse = substr( $_[0], 0, 1 ) eq '!';
    my $task    = $reverse ? substr( $_[0], 1 ) : $_[0];

    if (DEBUG) {
        Cpanel::Debug::log_info("Processing If Tag: ($task) TYPE=feature");
    }
    if ( $task =~ tr/\>\< // ) {
        substr( $task, -1, 1, '' ) if substr( $task, -1 ) eq '>';
        $task =~ s/[\r\n\t ]+$// if substr( $task, -1 ) =~ tr{\r\n\t }{};
        $task =~ s/^\s*\<*cpanelfeature\s*// if index( $task, '<' ) > -1;
    }

    my $featureresult;
    if ( $task =~ tr/\|\(\)\&\! // ) {
        my ( $op, $feature_string, $add_to_end, $first_char, $reverse_featureop, $last_char, $feature_key ) = ( 'or', '(', '', '', 0, 0 );

        # $feature_string --  Build a string for later eval
      FEATURELOOP:
        foreach my $featureop ( split( /\s+/, $task ) ) {
            if (DEBUG) {
                Cpanel::Debug::log_info("execiftag feature tag [$task] processing featureop [$featureop]");
            }

            # Simple case where items are spaced out
            if ( $featureop eq '!' ) {
                $reverse_featureop++;
                next;
            }
            elsif ( $featureop eq '(' || $featureop eq ')' ) {
                $feature_string .= ' ' . $featureop;
                next;
            }
            elsif ( $featureop eq 'or' || $featureop eq '||' ) {
                $feature_string .= ' ||';
                next;
            }
            elsif ( $featureop eq 'and' || $featureop eq '&&' ) {
                $feature_string .= ' &&';
                next;
            }

            # Next look and first char for negation or grouping
            my $first_char = substr( $featureop, 0, 1 );
            if ( $first_char eq '(' ) {
                $feature_string .= ' (';
                $featureop = substr( $featureop, 1 );

                # One grouping found look for possible others
                while ( substr( $featureop, 0, 1 ) eq '(' ) {
                    $feature_string .= ' (';
                    $featureop = substr( $featureop, 1 );
                }

                # Reset the first_char as it may be a negation
                $first_char = substr( $featureop, 0, 1 );
            }

            # Negation char
            while ( $first_char eq '!' ) {
                $reverse_featureop++;
                $featureop = substr( $featureop, 1 );
                if ( $featureop eq '!' ) {
                    $reverse_featureop++;
                    next FEATURELOOP;
                }
                else {
                    $first_char = substr( $featureop, 0, 1 );
                }
            }

            # Next look at last character for grouping
            ( $last_char, $add_to_end ) = ( substr( $featureop, -1, 1 ), '' );

            # has to be added after featureop's value
            if ( $last_char eq ')' ) {
                $add_to_end = ' )';
                $featureop  = substr( $featureop, 0, ( length($featureop) - 1 ) );

                # Don't skip closing groupings
                while ( substr( $featureop, -1, 1 ) eq ')' ) {
                    $add_to_end .= ' )';
                    $featureop = substr( $featureop, 0, ( length($featureop) - 1 ) );
                }
            }

            # The "real" feature check
            $feature_string .= ' ' . ( Cpanel::hasfeature($featureop) || 0 );

            if ($reverse_featureop) {
                if ( $reverse_featureop % 2 != 0 ) {
                    my $rev_char = substr( $feature_string, -1, 1 );
                    if ($rev_char) {
                        $rev_char = '0';
                    }
                    else {
                        $rev_char = '1';
                    }
                    $feature_string = substr( $feature_string, 0, ( length($feature_string) - 1 ) );
                    $feature_string .= $rev_char;
                }
                $reverse_featureop = 0;
            }

            $feature_string .= $add_to_end;
        }
        $feature_string .= ' )';

        $featureresult = eval $feature_string;    ## no critic qw(ProhibitStringyEval)

        if ( !defined $featureresult || $featureresult eq '' ) {
            Cpanel::Debug::log_warn("execiftag feature tag [$task] improperly formed. eval string [$feature_string]");
        }
        elsif (DEBUG) {
            Cpanel::Debug::log_warn("execiftag feature tag [$task] eval string [$feature_string] result [$featureresult]");
        }
        if (DEBUG) {
            Cpanel::Debug::log_info( "CpanelIf Result TYPE=feature MODE=complex (0 = show, 1 = skip): " . ( $reverse ? $featureresult : ( $featureresult ? 0 : 1 ) ) );
        }
    }
    else {
        $featureresult = Cpanel::hasfeature($task);
        if (DEBUG) {
            Cpanel::Debug::log_info( "CpanelIf Result TYPE=feature MODE=simple (0 = show, 1 = skip): " . ( $reverse ? $featureresult : ( $featureresult ? 0 : 1 ) ) );
        }
    }
    return $reverse ? ( $featureresult ? 0 : 1 ) : $featureresult;

}

sub set_nullif          { return ( $nullif        = shift ); }
sub set_nullfeatureif   { return ( $nullfeatureif = shift ); }
sub get_nullif          { return $nullif; }
sub get_nullfeatureif   { return $nullfeatureif; }
sub off                 { return ( $nullif || $nullfeatureif ); }
sub on                  { return ( !$nullif && !$nullfeatureif ); }
sub resetfeature_and_if { return ( ( $nullif, $nullfeatureif ) = ( 0, 0 ) ); }

1;
