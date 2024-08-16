package Cpanel::ExpVar;

# cpanel - Cpanel/ExpVar.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::ExpVar

=cut

use strict;
use Cpanel::ExpVar::Cache     ();
use Cpanel::ExpVar::Form      ();
use Cpanel::ExpVar::MultiPass ();
use Cpanel::Encoder::Tiny     ();

our $VERSION = '1.4';

# moved functions

my ($locale);

sub safeexpvar {
    return expvar( $_[0], 0, 0, 1 );
}

=head2 C<expand_and_detaint()>

This function is intended to detaint only the expanded portion of an expvar template.

It takes an expvar string and a coderef as input. The coderef must take a string as
input and return the string with any necessary escaping applied.

For example, a template of "xyzzy$FORM{abcd}123" will apply the detaint coderef to
to value of $Cpanel::FORM{abcd} and interpolate it between "xyzzy" and "123".

=cut

sub expand_and_detaint {
    my $expansion_template = shift;
    my $detaint_coderef    = shift;
    unless ( defined $detaint_coderef ) {
        require Carp;
        Carp::croak('No detaint coderef supplied');
    }

    # Existing cache values will not have the detaint and shouldn't be used.
    # New cahce values should only be stored for the current expansion.
    local %Cpanel::ExpVar::Cache::VARCACHE = ();

    return expvar( $expansion_template, 0, 1, 0, $detaint_coderef );
}

sub expvar {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $arg, $cleanresult, $nologic, $form_vars_only, $detaint_coderef, $isexpandable, $reverse, $notequalto ) = (
        $_[0],                                                    # 1st Argument: The actual expansion item to process
                                                                  # This is auto stripped of trailing and leading ",'
        $_[1],                                                    # 2nd Argument: Clean Result or not (html encode)
        $_[2],                                                    # 3rd Argument: Do we need to use the logic (=) below?
        $_[3],                                                    # 4th Argument: Should we only do form vars?
        $_[4],                                                    # 5th Argument: coderef for detainting interpolated data (cache handling currently broken when passed directly)
        ( $_[0] =~ tr/\$\{\%// || $_[0] eq 'DOMAIN' ? 1 : 0 ),    # If the 1st Argument contains expandable items or not
        0,                                                        # If we need to reverse the result (detected from 1st Argument later)
        's'                                                       # Initialize the $notequalto variable
    );

    if ( $arg =~ tr/\"\'// && ( substr( $arg, 0, 1 ) eq q{"} || substr( $arg, 0, 1 ) eq q{'} ) ) {
        substr( $arg, 0, 1, '' ) while ( index( $arg, q{'} ) == 0 || index( $arg, q{"} ) == 0 );
        chop($arg) while ( substr( $arg, -1 ) eq q{'} || substr( $arg, -1 ) eq q{"} );
    }

    # If we do not need to use the logic engine and the variable cannot be exapnded there is no point in processing it
    # at this point we just skip expvar and return the variable
    return $arg if ( $nologic && !$isexpandable );

    print STDERR "Cpanel::ExpVar (DEBUG) PreExpansion: $arg\n" if ( $Cpanel::CPVAR{'debug'} );

    if ( rindex( $arg, '!', 0 ) == 0 ) {
        if ( rindex( $arg, '!=', 0 ) == 0 && $arg =~ s/^\!\=(\d+)\,?// ) {
            $notequalto = $1;
        }
        else {
            substr( $arg, 0, rindex( $arg, '!,', 0 ) == 0 ? 2 : 1, '' );
            $reverse = 1;
        }
    }

    if ( Cpanel::ExpVar::Cache::has_expansion( { raw => $arg } ) ) {
        return ( $reverse ? ( !Cpanel::ExpVar::Cache::expand( { raw => $arg } ) ? 1 : 0 ) : Cpanel::ExpVar::Cache::expand( { raw => $arg } ) );
    }

    if ( !$nologic && $arg =~ tr/=// ) {
        if ( index( $arg, '=' ) != 0 && ( index( $arg, '=ltet=' ) > -1 || index( $arg, '=gtet=' ) > -1 || index( $arg, '==' ) > -1 || index( $arg, '=et=' ) > -1 || index( $arg, '=lt=' ) > -1 || index( $arg, '=gt=' ) > -1 ) ) {
            my ($operator) = $arg =~ /(=ltet=|=gtet=|==|=et=|=lt=|=gt=)/;
            my ( $exp1, $exp2 ) = split( /\Q$operator\E/, $arg, 2 );
            my ( $opresult, $expanded_exp1, $expanded_exp2 ) = ( 0, expvar( $exp1, 0, 1 ), expvar( $exp2, 0, 1 ) );
            if ( $operator eq '==' || $operator eq '=et=' ) {
                if ( $expanded_exp1 eq $expanded_exp2 ) { $opresult = 1; }
            }
            elsif ( $operator eq '=gtet=' ) {
                if ( $expanded_exp1 >= $expanded_exp2 ) { $opresult = 1; }
            }
            elsif ( $operator eq '=ltet=' ) {
                if ( $expanded_exp1 <= $expanded_exp2 ) { $opresult = 1; }
            }
            elsif ( $operator eq '=gt=' ) {
                if ( $expanded_exp1 > $expanded_exp2 ) { $opresult = 1; }
            }
            elsif ( $operator eq '=lt=' ) {
                if ( $expanded_exp1 < $expanded_exp2 ) { $opresult = 1; }
            }
            if ($opresult) {
                return $reverse ? 0 : 1;
            }
            else {
                return $reverse ? 1 : 0;
            }
        }
    }
    if ( !$isexpandable ) {

        # If arg is not expandable, there is no point in processing it any more
        # You may wonder why this block skips $cleanresult processing. It's because spaghetti tastes delicious.
        return (
            $reverse
            ? ( !$arg ? 1 : 0 )
            : $arg
        );
    }

    my $processed_string = '';

    if ( $arg eq '%FORM' ) {

        # Oddball syntax
        return \%Cpanel::FORM;
    }
    else {
        ## Main interpolation loop

        # The $form_vars_only variable has very odd behavior of stopping at the first match and
        # bypassing the normal return logic, but only in the case where there was at least one match.
        # The behavior is preserved here, though it does seem nonsensical.
        # $skip_further_processing tracks this state.
        my $skip_further_processing = 0;

        foreach my $token ( tokenize_expvar_string($arg) ) {
            if ( !$skip_further_processing && Cpanel::ExpVar::Form::has_expansion($token) ) {

                # $FORM{var} is the only expansion type that cares about $cleanresult.
                # The logic is used is few places in cPanel's codebase and should be removed in a
                # future major release to make the expansions more consistent. It has been retained
                # for now to preserve the existing API behavior.
                $processed_string .= Cpanel::ExpVar::Form::expand( $token, $detaint_coderef, $cleanresult );

                if ($form_vars_only) {

                    # Special case described above
                    $skip_further_processing = 1;
                }
            }
            elsif ( !$skip_further_processing && !$form_vars_only ) {
                if ( Cpanel::ExpVar::Cache::has_expansion($token) ) {
                    $processed_string .= Cpanel::ExpVar::Cache::expand( $token, $detaint_coderef );
                }
                elsif ( Cpanel::ExpVar::MultiPass::has_expansion($token) ) {
                    $processed_string .= Cpanel::ExpVar::MultiPass::expand( $token, $detaint_coderef );
                }
                else {
                    $processed_string .= $token->{raw};
                }
            }
            else {
                $processed_string .= $token->{raw};
            }
        }

        # special case described above
        return $processed_string if ($skip_further_processing);
    }

    # Final processing
    if ($cleanresult) { $arg = Cpanel::Encoder::Tiny::safe_html_encode_str($processed_string); }

    if ( $Cpanel::CPVAR{'debug'} ) {
        print STDERR "Cpanel::ExpVar (DEBUG) PostExpansion: $processed_string\n";
        print STDERR "Cpanel::ExpVar (DEBUG) PostExpansion (reverse): $reverse\n";
    }

    if ($reverse) {
        return ( !$processed_string ? 1 : 0 );
    }
    return ( ( $notequalto ne 's' && $processed_string ne $notequalto ) ? 1 : $processed_string );
}

=head2 C<tokenize_expvar_string()>

Takes an expvar string as input and returns an array of individual tokens
inside the string that can be processed by C<interpolate_expvar_token>.
This does NOT support embedding tags inside one another ( IE: $ENV{$ENV{foo}} )

Individual tokens are hashyrefs containing:
raw => original combined expansion string
expansion => expansion string
arg => arguments to the expansion
extra => unexpandable data following the expansion string (IE: $exp1{arg}extra$exp2)

=cut

sub tokenize_expvar_string {
    my $str = shift;
    return { raw => $str } unless index( $str, '$' ) > -1;
    if ( substr( $str, 0, 1 ) eq '$' && $str !~ tr/a-z$//c && ( $str =~ tr/$// ) == 1 ) {
        return ( { raw => $str, expansion => substr( $str, 1 ), arg => undef, extra => undef } );
    }
    my @tokens;
    if ( rindex( $str, '$', 0 ) != 0 ) {
        push @tokens, { raw => substr( $str, 0, index( $str, '$' ), '' ) };
    }
    while ( $str =~ s/\A(\$([^\${\s]*)(?:{['"]?([^"'}]+)['"]?})?([^\$]+)?)//g ) {
        push @tokens, { raw => $1, expansion => $2, arg => $3, extra => $4 };
    }
    return @tokens;
}

1;
