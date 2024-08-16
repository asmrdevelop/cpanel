package Cpanel::SMTP::HELO;

# cpanel - Cpanel/SMTP/HELO.pm                     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SMTP::HELO

=head1 SYNOPSIS

    my $helo_obj = Cpanel::SMTP::HELO->load();

    # This should normally be the domain’s mail IP’s PTR value.
    my $helo = $helo_obj->get_helo_for_domain('example.com');

=head1 DESCRIPTION

An object interface to the system’s SMTP HELO configuration.

=cut

#----------------------------------------------------------------------

use Cpanel::ConfigFiles        ();
use Cpanel::Config::LoadConfig ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $helo_obj = I<CLASS>->load()

Returns a reference to an instance of this class.

=cut

sub load {
    my ($class) = @_;

    my $self = scalar Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::MAILHELO_FILE, undef, ': ' );

    return bless $self, $class;
}

#----------------------------------------------------------------------

=head2 $helo = I<OBJ>->get_helo_for_domain( $DOMAIN )

Returns the HELO that the server will send when sending $DOMAIN’s mail.

Note that, ordinarily, all domains that use a given IP address to send mail
should use the same HELO. In fact,
C<Cpanel::DnsUtils::MailRecords::validate_ptr_records_for_domains()>
more or less enforces this by considering as invalid any setup where the
sending domain’s mail IP’s PTR value does not equal the sending domain’s HELO.

=cut

my $_hostname;

sub get_helo_for_domain {
    my ( $self, $domain ) = @_;

    return $self->{$domain} || $self->{'*'} || (
        $_hostname ||= do {
            require Cpanel::Hostname;
            Cpanel::Hostname::gethostname();
        }
    );
}

1;
