package Cpanel::HTTP::Tiny::FastSSLVerify;

# cpanel - Cpanel/HTTP/Tiny/FastSSLVerify.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'HTTP::Tiny';

use Cpanel::PublicSuffix ();

my $orig_handle_connect = \&HTTP::Tiny::Handle::connect;

our $VERSION = '1.0';

use constant NO_VERIFY_TOUCHFILE_PATH => '/var/cpanel/no_verify_SSL';

sub new {
    my ( $class, %opts ) = @_;

    my $connect_timeout = delete $opts{'connect_timeout'};

    my $ssl_opts_hr = $opts{'SSL_options'};
    $ssl_opts_hr &&= {%$ssl_opts_hr};

    #Caller can’t override this one because that would defeat this point
    #of using this module! :)
    $ssl_opts_hr->{'SSL_verifycn_publicsuffix'} = Cpanel::PublicSuffix::get_io_socket_ssl_publicsuffix_handle();

    my $verify_ssl = 1;

    # No verify ssl for testing purposes
    if ( -f NO_VERIFY_TOUCHFILE_PATH ) {
        $verify_ssl = 0;
    }

    my $self = $class->SUPER::new(
        'verify_SSL' => $verify_ssl,
        %opts,
        'SSL_options' => $ssl_opts_hr,
    );

    $self->{'connect_timeout'} = $connect_timeout if $connect_timeout;
    return $self;
}

sub request {
    my ( $self, @args ) = @_;

    # Hack to allow setting the connect timeout different from the read timeout
    # cf. https://github.com/chansen/p5-http-tiny/issues/107
    no warnings 'redefine';
    local *HTTP::Tiny::Handle::connect = sub {
        my ( $connect_self, @args ) = @_;
        local $connect_self->{'timeout'} = $self->{'connect_timeout'};
        return $orig_handle_connect->( $connect_self, @args );
      }
      if ( $self->{'connect_timeout'} );
    use warnings 'redefine';

    return $self->SUPER::request(@args);

}

1;
