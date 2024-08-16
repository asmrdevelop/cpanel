package Cpanel::Time::Split;

# cpanel - Cpanel/Time/Split.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Time::Split - Logic for splitting time deltas into units

=cut

#----------------------------------------------------------------------

use Cpanel::Context ();

my $one_minute = 60;
my $one_hour   = 60 * $one_minute;
my $one_day    = 24 * $one_hour;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($days, $hours, $minutes, $seconds) = epoch_to_dhms( $SECONDS )

Converts $SECONDS into a list of days, hours, minutes, and seconds.

=cut

sub epoch_to_dhms {
    my ($total_seconds) = @_;

    Cpanel::Context::must_be_list();

    return (
        int( $total_seconds / $one_day ),    #days
        epoch_to_hms( $total_seconds % $one_day + ( $total_seconds - int($total_seconds) ) ),
    );
}

=head2 ($hours, $minutes, $seconds) = epoch_to_hms( $SECONDS )

Like C<epoch_to_dhms()>, but hours are the largest time unit this will
return.

=cut

sub epoch_to_hms {
    my ($total_seconds) = @_;

    Cpanel::Context::must_be_list();

    return (
        int( $total_seconds / $one_hour ),                                          #hours
        int( ( $total_seconds % $one_hour ) / $one_minute ),                        #minutes
        $total_seconds % $one_minute + ( $total_seconds - int($total_seconds) ),    #seconds
    );
}

#This will ensure that there is always a number for each of six fields,
#even if the passed-in string is incomplete. Note that there must
#always be a year.
sub string_to_ymdhms {
    my ($str) = @_;

    Cpanel::Context::must_be_list();

    return map { $_ || 0 } ( $str =~ m<[0-9]+>g )[ 0 .. 5 ];
}

=head2 @strings = seconds_to_locale_list( $SECONDS )

Returns a list of strings, e.g., C<2 days> and C<3 seconds>, that together
describe $SECONDS as localized strings.

The output from this function is suitable for inclusion into a locale string
via the C<list_and()> function, e.g.:

    my @split = seconds_to_locale_list($elapsed);

    locale()->maketext('Elapsed: [list_and,_1]', \@split);  ## no extract maketext

It is recommended that your string B<not> depend on plural forms since
different languages may pluralize lists differently.

=cut

sub seconds_to_locale_list ($secs) {
    Cpanel::Context::must_be_list();

    my @dhms = epoch_to_dhms($secs);

    my $lh = _locale();

    my @times;
    if ( $dhms[3] ) {
        unshift @times, $lh->maketext( '[quant,_1,second,seconds]', $dhms[3] );
    }
    if ( $dhms[2] ) {
        unshift @times, $lh->maketext( '[quant,_1,minute,minutes]', $dhms[2] );
    }
    if ( $dhms[1] ) {
        unshift @times, $lh->maketext( '[quant,_1,hour,hours]', $dhms[1] );
    }
    if ( $dhms[0] ) {
        unshift @times, $lh->maketext( '[quant,_1,day,days]', $dhms[0] );
    }

    return @times;
}

=head2 $string = seconds_to_locale( $SECONDS )

Like C<seconds_to_locale_list()> but applies C<list_and()> for you
and returns a string.

=cut

sub seconds_to_locale ($secs) {
    return _locale()->list_and( seconds_to_locale_list($secs) );
}

=head2 $string = seconds_to_elapsed( $SECONDS )

Like C<seconds_to_locale()> but returns a phrase that states that
$SECONDS have “elapsed”. This is nontrivial; see the code for details.

=cut

sub seconds_to_elapsed ($seconds) {
    my ( $h, $m, $s ) = Cpanel::Time::Split::epoch_to_hms($seconds);

    # We need separate phrases for each of these because a translator
    # may need to do number/gender agreement with the word “elapsed”
    # differently in various languages. It would be much simpler if we
    # could just use seconds_to_locale(), but the translator won’t know
    # how to inflect the translation of “elapsed” in, e.g., French.

    if ($h) {
        if ($m) {
            if ($s) {
                return _locale()->maketext( '[comment,parenthetical][quant,_1,hour,hours], [quant,_2,minute,minutes], and [quant,_3,second,seconds] elapsed', $h, $m, $s );
            }

            return _locale()->maketext( '[comment,parenthetical][quant,_1,hour,hours] and [quant,_2,minute,minutes] elapsed', $h, $m );
        }
        elsif ($s) {
            return _locale()->maketext( '[comment,parenthetical][quant,_1,hour,hours] and [quant,_2,second,seconds] elapsed', $h, $s );
        }

        return _locale()->maketext( '[comment,parenthetical][quant,_1,hour,hours] elapsed', $h );
    }
    elsif ($m) {
        if ($s) {
            return _locale()->maketext( '[comment,parenthetical][quant,_1,minute,minutes] and [quant,_2,second,seconds] elapsed', $m, $s );
        }

        return _locale()->maketext( '[comment,parenthetical][quant,_1,minute,minutes] elapsed', $m );
    }

    return _locale()->maketext( '[comment,parenthetical][quant,_1,second,seconds] elapsed', $s );
}

my $_locale;

sub _locale {
    return $_locale ||= do {
        local ( $!, $@ );
        require Cpanel::Locale;

        Cpanel::Locale->get_handle();
    };
}

1;
