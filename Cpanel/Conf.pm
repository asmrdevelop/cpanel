package Cpanel::Conf;

# cpanel - Cpanel/Conf.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::Constants ();
my $cpanel_theme;
my $webmail_theme;

sub new {
    my ( $class, %opts ) = @_;
    my $self = {};
    bless $self, $class;
    if ( exists $opts{'wwwacct'} && ref $opts{'wwwacct'} eq 'HASH' ) {
        $self->{'wwwacct'} = $opts{'wwwacct'};
    }

    # Reset internal caches
    undef $cpanel_theme;
    undef $webmail_theme;

    return $self;
}

sub system_config_dir {
    my ($self) = @_;
    return '/etc';
}

sub product_config_dir {
    my ($self) = @_;
    return '/var/cpanel';
}

sub product_base_dir {
    my ($self) = @_;
    return '/usr/local/cpanel';
}

sub whm_base_dir {
    my ($self) = @_;
    return $self->product_base_dir . '/whostmgr';
}

sub cpanel_theme_dir {
    my ($self) = @_;
    return $self->product_base_dir . '/base/frontend';
}

sub whm_theme_dir {
    my ($self) = @_;
    return $self->whm_base_dir . '/docroot/themes';
}

sub whm_theme {
    my ($self) = @_;
    return 'x';
}

sub account_creation_defaults {
    my ($self) = @_;
    if ( exists $self->{'wwwacct'} ) {
        my %wwwacct = %{ $self->{'wwwacct'} };
        return \%wwwacct;
    }
    require Cpanel::Config::LoadWwwAcctConf;
    return Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
}

sub cpanel_theme {
    my ($self) = @_;
    return $cpanel_theme if defined $cpanel_theme;

    $cpanel_theme = $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;

    my $defaults = {};
    $defaults = $self->account_creation_defaults();
    if ( ref $defaults eq 'HASH' && $defaults->{'DEFMOD'} ) {
        $cpanel_theme = $defaults->{'DEFMOD'};
    }
    return $cpanel_theme;
}

sub default_webmail_theme {
    my ($self) = @_;
    return $webmail_theme if defined $webmail_theme;

    $webmail_theme = $Cpanel::Config::Constants::DEFAULT_WEBMAIL_THEME;

    my $defaults = {};
    $defaults = $self->account_creation_defaults();
    if ( ref $defaults eq 'HASH' && $defaults->{'DEFMOD'} ) {
        $webmail_theme = $defaults->{'DEFMOD'};
    }
    return $webmail_theme;
}

1;
