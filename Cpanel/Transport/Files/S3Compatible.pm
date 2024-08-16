
# cpanel - Cpanel/Transport/Files/S3Compatible.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::S3Compatible;

=head1 NAME

Cpanel::Transport::Files::S3Compatible

=head1 DESCRIPTION

The module implements the transport for non-Amazon S3 backup destinations.

=head1 SYNOPSIS

    The module is based off of the AmazonS3 transport module.  The main difference
    from the parent module is that it requires the "host" to explicitly set
    since it will not be connecting to Amazon.

=cut

use strict;
use warnings;

use Cpanel::Transport::Files::AmazonS3 ();

our @ISA = ('Cpanel::Transport::Files::AmazonS3');

=head1 SUBROUTINES

=head2 _get_valid_parameters

Returns a list of parameters allowed for this module.

=cut

sub _get_valid_parameters {

    my @result = Cpanel::Transport::Files::AmazonS3::_get_valid_parameters();

    push @result, 'host';

    return @result;
}

=head2 _missing_parameters

Inspect a hash of parameters and return a list of any
expected parameters not present.

=over 3

=item C<< $param_hashref >>

A hash reference containing the parameters mapped to values

=back

=cut

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = Cpanel::Transport::Files::AmazonS3::_missing_parameters($param_hashref);

    if ( !defined $param_hashref->{'host'} ) {
        push @result, 'host';
    }

    return @result;
}

=head2 _validate_parameters

Inspect a hash of parameters and return a list of any
expected parameters with invalid values.

=over 3

=item C<< $param_hashref >>

A hash reference containing the parameters mapped to values

=back

=cut

sub _validate_parameters {
    my ($param_hashref) = @_;

    my @result = Cpanel::Transport::Files::AmazonS3::_validate_parameters($param_hashref);

    if ( !defined $param_hashref->{'host'} || !$param_hashref->{'host'} ) {
        push @result, 'host';
    }

    return @result;
}

1;
