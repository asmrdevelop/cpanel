package Cpanel::Email::Filter::Spam;

# cpanel - Cpanel/Email/Filter/Spam.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Filter::Spam - logic for spam filters in Exim filters

=head1 SYNOPSIS

    Cpanel::Email::Filter::Spam::verify_valid_spam_score($score);

    my $filter = Cpanel::Email::Filter::Spam::generate_spam_filter_for_score($score);

    my @filters = Cpanel::Email::Filter::Spam::get_autodelete_filters($fstore);

=cut

use Cpanel::Context    ();
use Cpanel::LoadModule ();

our $RULE_VERSION = 2;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 verify_valid_spam_score( SCORE )

Throws an appropriate exception if SCORE is not a valid spam score
(i.e., positive integer).

=cut

sub verify_valid_spam_score {
    my ($score) = @_;

    if ( !$score || $score =~ tr<0-9><>c ) {
        die "“$score” is not a valid spam score.";
    }

    return;
}

=head2 $filter_str = generate_spam_filter_for_score( SCORE )

Returns an Exim filter string that rejects any message whose C<X-Spam-Bar>
indicates a spam score that is at least the given SCORE. This is the most
recent format for filtering spam messages.

=cut

sub generate_spam_filter_for_score {
    my ($score) = @_;

    verify_valid_spam_score($score);

    my $score_str = '+' x $score;

    return <<"END";
#Generated Apache SpamAssassin™ Discard Rule (version $RULE_VERSION)
if
 \$h_X-Spam-Bar: contains "$score_str"
then
 save "/dev/null" 660
endif

END
}

=head2 @filters = get_autodelete_filters( FSTORE )

Returns a list of hashes that represent recognized spam filters.
FSTORE is the return of C<Cpanel::Email::Filter::_fetchfilter()>.
(Despite its name, that function is often called publicly.)

The returned hashes each look like:

=over

=item * C<filtername> - The name of the filter.

=item * C<spam_delete_score> - The spam score that the filter acts upon.
Note that filters that don’t act on the C<X-Spam-Bar> header (i.e., that
don’t use this most recent of filtering methods) will inherit
the C<required_score> setting from the user’s SpamAssassin configuration.

=back

=cut

sub get_autodelete_filters {
    my $fstore = shift;

    Cpanel::Context::must_be_list();

    my @autodel_filters;

    if ( $fstore->{'filter'} ) {

        #For each filter, go through and determine if the filter is
        #a spam autodelete filter:
        #
        #   1) At least one rule must match one of the patterns below.
        #   2) At least one action must look like “save” -> “/dev/null”.
        #
        for my $filter_hr ( @{ $fstore->{'filter'} } ) {

          RULE:
            for my $rule_hr ( @{ $filter_hr->{'rules'} } ) {
                my $part_lc = $rule_hr->{'part'} =~ tr<A-Z><a-z>r;

                my $is_spam_bar;

                #Look for a rule match. (It only takes one.)
                my $match = grep { index( $part_lc, $_ ) == 0 } (
                    '$h_x-spam-bar:',
                    '$header_x-spam-bar:',
                );

                $is_spam_bar = $match;

                $match ||= grep { index( $part_lc, $_ ) == 0 } (
                    '$h_x-spam-score:',
                    '$header_x-spam-score:',
                );

                if ( !$match ) {
                    $match = grep { index( $part_lc, $_ ) == 0 } (
                        '$h_x-spam-status:',
                        '$header_x-spam-status:',
                    );

                    $match &&= $rule_hr->{'match'} eq 'begins';
                    $match &&= ( substr( $rule_hr->{'val'}, 0, 1 ) =~ tr<Y><y>r ) eq 'y';
                }

                if ( !$match ) {
                    $match = grep { index( $part_lc, $_ ) == 0 } (
                        '$h_subject:',
                        '$header_subject:',
                    );

                    $match &&= $rule_hr->{'val'} =~ m/^\*+SPAM\*+$/;
                }

                next RULE if !$match;

              ACTION:
                for my $action_hr ( @{ $filter_hr->{'actions'} } ) {

                    #Now look for an action match. (Again, it only takes one.)
                    next ACTION if $action_hr->{'action'} !~ m/^save/i;
                    next ACTION if $action_hr->{'dest'}   !~ m<^/dev/null>;

                    #If we get here then we’ve satisfied both of the criteria
                    #for a match. Now add the filter’s name and spam score
                    #to the return list.

                    my $filter_score;

                    #This is the most up-to-date variant of the cpuser spam
                    #filter. It stores a spam score inside the filter,
                    #represented as the number of “+” symbols.
                    if ($is_spam_bar) {
                        $filter_score = ( $rule_hr->{'val'} =~ tr/\+// );
                    }
                    else {

                        #Previous spam filter formats didn’t encode a score
                        #using “+” signs. In this case we get the score
                        #from the user’s SpamAssassin configuration.
                        Cpanel::LoadModule::load_perl_module('Cpanel::SpamAssassin::Config');
                        $filter_score = Cpanel::SpamAssassin::Config::get_config_option('required_score');
                    }

                    push @autodel_filters, {
                        'filtername'        => $filter_hr->{'filtername'},
                        'spam_delete_score' => $filter_score,
                    };

                    last ACTION;
                }

                last RULE;
            }
        }
    }

    return @autodel_filters;
}

1;
