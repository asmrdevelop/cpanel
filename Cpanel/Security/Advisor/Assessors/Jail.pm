package Cpanel::Security::Advisor::Assessors::Jail;

# cpanel - Cpanel/Security/Advisor/Assessors/Jail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::PwCache::Build ();
use Cpanel::Config::Users  ();

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_unjailed_users();

    return 1;
}

sub _check_for_unjailed_users {
    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    if ( !$self->cagefs_is_enabled() ) {
        if ( -e '/var/cpanel/conf/jail/flags/mount_usr_bin_suid' ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Jail_mounted_user_bin_suid',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('Jailshell is mounting /usr/bin suid, which allows escaping the jail via crontab.'),
                    'suggestion' => $self->_lh->maketext(
                        'Disable “Jailed /usr/bin mounted suid” in the “[output,url,_1,Tweak Settings,_2,_3]” area',
                        $self->base_path('scripts2/tweaksettings?find=jailmountusrbinsuid'),
                        'target',
                        '_blank'
                    ),
                }
            );
        }

        Cpanel::PwCache::Build::init_passwdless_pwcache();
        my %cpusers          = map { $_ => undef } Cpanel::Config::Users::getcpusers();
        my %wheel_users_hash = map { $_ => 1 } split( ' ', ( getgrnam('wheel') )[3] // '' );
        delete $wheel_users_hash{'root'};    # We don't care about root being in the wheel group

        my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

        my @users = map { $_->[0] } grep { exists $cpusers{ $_->[0] } && $_->[8] && $_->[8] !~ m{(?:false|nologin|(?:no|jail)shell)} } @$pwcache_ref;    #aka users without jail or noshell
        my @users_without_jail;
        my @wheel_users;

        foreach my $user (@users) {
            if ( $wheel_users_hash{$user} ) {
                push( @wheel_users, $user );
            }
            else {
                push( @users_without_jail, $user );
            }
        }

        @users_without_jail = sort @users_without_jail;    # Always notify in the same order
        if ( scalar @users_without_jail > 100 ) {
            splice( @users_without_jail, 100 );
            push @users_without_jail, '..truncated..';
        }

        if (@wheel_users) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Jail_wheel_users_exist',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_INFO,
                    'text'       => $self->_lh->maketext('Users with wheel group access:'),
                    'suggestion' => $self->_lh->maketext( '[list_and,_1].', \@wheel_users ) . '<br><br>' . $self->_lh->maketext(
                        'Users in the “[asis,wheel]” group may run “[asis,su]”. Consider removing these users from the “[asis,wheel]” group in the “[output,url,_1,Manage Wheel Group Users,_2,_3]” area if they do not need to be in the “[asis,wheel]” group.',
                        $self->base_path('scripts/modwheel'),
                        'target',
                        '_blank'
                    ),
                }
            );
        }

        if (@users_without_jail) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Jail_users_running_outside_of_jail',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_WARN,
                    'text'       => $self->_lh->maketext('Users running outside of the jail:'),
                    'suggestion' => $self->_lh->maketext( '[list_and,_1].', \@users_without_jail ) . '<br><br>' . $self->_lh->maketext(
                        'Change these users to jailshell or noshell in the “[output,url,_1,Manage Shell Access,_2,_3]” area.',
                        $self->base_path('scripts2/manageshells'),
                        'target',
                        '_blank'

                    ),
                }
            );
        }
    }

    return 1;
}

1;
