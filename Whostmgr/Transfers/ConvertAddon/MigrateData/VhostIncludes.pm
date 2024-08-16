package Whostmgr::Transfers::ConvertAddon::MigrateData::VhostIncludes;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/VhostIncludes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use File::Spec                  ();
use Cpanel::Exception           ();
use Cpanel::SafeDir::MK         ();
use Cpanel::FileUtils::Copy     ();
use Cpanel::HttpUtils::Version  ();
use Cpanel::ConfigFiles::Apache ();

sub new {
    my ( $class, $opts ) = @_;

    my $self = $class->SUPER::new($opts);
    $self->{'includes_basedir'} = Cpanel::ConfigFiles::Apache->new()->dir_conf_userdata();
    $self->{'apache_version'}   = Cpanel::HttpUtils::Version::get_current_apache_version_key() || 2;

    return $self;
}

sub copy_custom_vhost_includes_for_domain {
    my ( $self, $domain_info_hr ) = @_;

    if ( !( $domain_info_hr && 'HASH' eq ref $domain_info_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }
    $self->ensure_users_exist();

    my $includes_copied = 0;
    foreach my $type (qw(ssl std)) {
        foreach my $domain ( $domain_info_hr->{'domain'}, $domain_info_hr->{'subdomain'} ) {
            next if !defined $domain;

            my $domain_includes = File::Spec->catdir( $self->{'includes_basedir'}, $type, $self->{'apache_version'}, $self->{'from_username'}, $domain );
            if ( -d $domain_includes ) {
                my $new_domain_includes = File::Spec->catdir( $self->{'includes_basedir'}, $type, $self->{'apache_version'}, $self->{'to_username'}, $domain_info_hr->{'domain'} );
                Cpanel::SafeDir::MK::safemkdir($new_domain_includes) if !-d $new_domain_includes;

                if ( opendir my $dir_dh, $domain_includes ) {
                    while ( my $conf_file = readdir $dir_dh ) {
                        next if $conf_file !~ m/\.conf$/;

                        my ( $ok, $err ) = Cpanel::FileUtils::Copy::safecopy( File::Spec->catfile( $domain_includes, $conf_file ), File::Spec->catfile( $new_domain_includes, $conf_file ) );
                        $self->add_warning($err) if !$ok;

                        $includes_copied++;
                    }
                }
            }
        }
    }

    if ( $self->has_user_level_includes() ) {
        $self->add_warning('User-Level VirtualHost Includes detected, but not copied. You must manually review and copy User-Level VirtualHost Includes.');
    }

    return $includes_copied;
}

sub has_user_level_includes {
    my $self = shift;

    my $includes_found = 0;
    foreach my $type (qw(ssl std)) {
        my $user_includes = File::Spec->catdir( $self->{'includes_basedir'}, $type, $self->{'apache_version'}, $self->{'from_username'} );
        next if !-d $user_includes;

        if ( opendir my $dir_dh, $user_includes ) {
            $includes_found += grep { $_ =~ m/\.conf$/ } readdir $dir_dh;
        }
    }

    return $includes_found;
}

1;
