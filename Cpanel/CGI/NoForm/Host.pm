package Cpanel::CGI::NoForm::Host;

# cpanel - Cpanel/CGI/NoForm/Host.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw{Cpanel::CGI::NoForm};

use Cpanel::CgiSys ();

=encoding utf-8

=head1 NAME

Cpanel::CGI::NoForm::Host

=head1 SYNOPSIS

See parent module's synopsis for usage info, just use this one as parent module instead.

=head1 DESCRIPTION

Made to enable code reuse between these pages in cgi-sys/:
* contact_details.cgi

=head1 METHODS

=head2 run()

Basically all we do here is __PACKAGE__->SUPER::run() after doing some basic verification and information gathering about the host/user.

=cut

sub run {
    my ($self) = @_;

    my $host2check = $ENV{'HTTP_HOST'} || $ENV{'SERVER_NAME'};
    $host2check or do {

        #We assume that the problem is the request, not Apache’s CGI
        #logic which should convert the Host header into HTTP_HOST.
        $self->die( 'No “Host” header given or SERVER_NAME set for webserver!', 400 );
    };
    @{$self}{qw(user owner host)} = Cpanel::CgiSys::get_site_details($host2check);

    return $self->SUPER::run(@_);
}

=head2 get_host_details()

Gives you back what was found about the site's owner and the host as an ARRAY. Used in various scripts over in cgi-sys/

=cut

sub get_host_details {
    my ($self) = @_;

    return ( $self->{'owner'}, $self->{'host'} );
}

1;
