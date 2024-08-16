# cpanel - Cpanel/SSL/Protocols.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::SSL::Protocols;

use strict;
use warnings;
use Cpanel::Imports;

use Cpanel::SSL::Defaults ();

=head1 NAME

Cpanel::SSL::Protocols - Interpret and manipulate SSL/TLS protocol version strings

=head1 DESCRIPTION

SSL/TLS protocol version strings come in a variety of flavors and have flexible
syntax. This module accommodates some, but not all, of those flavors. If you need
additional support, please extend the parsing capabilities in a way that retains
compatibility with the current unit tests.

=head1 FUNCTIONS

=head2 interpret_version_string(STRING)

Given an SSL/TLS protocol version string (colon-delimited), interprets the
operators to determine which available protocols will be active and which
will not and returns this information as a hash ref where each key present
indicates an active protocol.

Supported operators:

=over

=item * Add (+ or no operator)

=item * Remove (-)

=item * Exclude (!)

=back

The C<ALL> set is specified as C<SSLv23>.

The protocol separator may be '.' or '_', but it will be converted to '.'
in the returned data for predictability.

The protocol names must already be uppercase.

Example 1:

  my $active = Cpanel::SSL::Protocols::interpret_version_string($versions);
  if ( grep { $active->{$_} } qw(SSLv2 SSLv3 TLSv1 TLSv1.1) ) {
      die 'One or more outdated SSL/TLS versions are active.';
  }

Example 2:

  my $active = Cpanel::SSL::Protocols::interpret_version_string($versions);
  delete $active->{SSLv2};
  $active->{TLSv1_2} = 1;
  my $new_version_string = Cpanel::SSL::Defaults::format_protocol_list(
    [ keys %$active ],
    { type => 'negative', delimiter => ':', separator => '_', negation => '!' }
  );

=cut

sub interpret_version_string {
    my ($string) = @_;

    my $all_protos = Cpanel::SSL::Defaults::all_protos_ordered();
    my ( %active, %excluded );

    for my $action ( split /[: ]/, $string ) {
        my ( $operator, $protocol ) = $action =~ /^ ([^A-Z]?) ((?:all|(?:SSL|TLS)v[0-9._]+)) $/ix
          or die "Could not parse operator and protocol from action “$action”";

        $protocol =~ tr/_/./;
        $protocol =~ s/^(\w{3})([vV])/\U$1\L$2/g;

        if ( !length($operator) || $operator eq '+' ) {
            if ( $protocol eq 'SSLv23' || lc $protocol eq 'all' ) {    # "SSLv23" means "all protocols"
                $active{$_} = 1 for @$all_protos;
            }
            else {
                $active{$protocol} = 1;
            }
        }
        elsif ( $operator eq '-' ) {
            if ( $protocol eq 'SSLv23' || lc $protocol eq 'all' ) {
                %active = ();
            }
            else {
                delete $active{$protocol};
            }
        }
        elsif ( $operator eq '!' ) {
            if ( $protocol eq 'SSLv23' || lc $protocol eq 'all' ) {
                logger()->info('Encountered unusable protocol specification !SSLv23. Choosing to interpret this as -SSLv23 instead.');
                %active = ();
            }
            else {
                $excluded{$protocol} = 1;
            }
        }
        else {
            die "Encountered unknown operator “$operator”";
        }
    }
    delete @active{ keys %excluded };

    return \%active;
}

=head2 upgrade_version_string_for_tls_1_2

For cpsrvd/cpdavd only!

Given any TLS version string (colon-delimited), determine what the
oldest supported version is in it, and convert the version string
to one that retains support for that version while also ensuring
that any higher version (most importantly, TLSv1.2) is also allowed.

Example 1:

  Before: -SSLv23:TLSv1_1:TLSv1_2
   After: SSLv23:!SSLv2:!SSLv3:!TLSv1

Example 2:

  Before: SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1
   After: SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1 (unchanged, because this is already ideal)

Example 1:

  Before: TLSv1
   After: SSLv23:!SSLv2:!SSLv3

=cut

sub upgrade_version_string_for_tls_1_2 {
    my ($string) = @_;

    my $separator = '_';

    my $active = interpret_version_string($string);

    $active->{'TLSv1.2'} = 1;

    my $new_version_string = Cpanel::SSL::Defaults::format_protocol_list(
        [ keys %$active ],
        {
            delimiter => ':',
            type      => 'negative',
            negation  => '!',
            all       => 'SSLv23',
            separator => $separator,
        },
    );

    return $new_version_string;
}

=head2 upgrade_version_string_for_tls_1_2_apache

Same as C<upgrade_version_string_for_tls_1_2>, but uses the Apache SSLProtocol format.

=cut

sub upgrade_version_string_for_tls_1_2_apache {
    my ($string) = @_;

    my $active = interpret_version_string($string);

    # format_protocol_list isn't aware of TLSv1.3 yet, so take this shortcut
    return 'all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1' if $active->{'TLSv1.3'};

    $active->{'TLSv1.2'} = 1;

    my $new_version_string = Cpanel::SSL::Defaults::format_protocol_list(
        [ keys %$active ],
        {
            delimiter => ' ',
            type      => 'negative',
            negation  => '-',
            all       => 'all',
            separator => '.',
        },
    );

    return $new_version_string;
}

1;
