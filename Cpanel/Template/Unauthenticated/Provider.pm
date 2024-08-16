package Cpanel::Template::Unauthenticated::Provider;

# cpanel - Cpanel/Template/Unauthenticated/Provider.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

require base;

our @ISA = ('Template::Provider');

use Template::Constants ();
use Template::Provider  ();

use Cpanel::App        ();
use Cpanel::LoginTheme ();

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    return bless $self, $class;
}

sub fetch {
    my ( $self, $file ) = @_;

    my $docroot = $Cpanel::LoginTheme::DOCROOT;

    if ( 'SCALAR' eq ref $file ) {
        return $self->SUPER::fetch($$file);
    }
    else {
        my ( $basename, $ext ) = $file =~ m{\A(.*)(?:\.([^.]+))\z};

        my $found = Cpanel::LoginTheme::getloginfile(
            docname                => length $basename ? $basename : $file,
            docext                 => length $ext      ? $ext      : 'tmpl',
            docroot                => $docroot,
            appname                => $Cpanel::App::appname,
            logintheme             => scalar Cpanel::LoginTheme::get_login_theme(),
            check_default          => 1,
            allow_slash_in_docname => 1,
        );

        if ( length $found ) {
            local $self->{'ABSOLUTE'} = 1;
            return $self->SUPER::fetch($found);
        }
    }

    return ( undef, Template::Constants::STATUS_DECLINED );
}

1;
