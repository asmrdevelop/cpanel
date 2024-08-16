
# cpanel - Cpanel/UserManager/Services.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Services;

use strict;
use warnings;

## UNSHIPPED
# Cpanel/UserManager/Services.pm is unshipped because it loads unshipped
# modules, and so it would not be possible to use it from uncompiled code
# while on a binary install.

use Cpanel::UserManager::Annotation ();
use Cpanel::UserManager::Storage    ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::UserManager::Services

=head1 FUNCTIONS

=head2 setup_services_for(RECORD)

Based on the services marked as B<enabled> in the provided object, this function sets up any
service accounts that will be needed and marks them as linked to the sub-account.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object - The account for which to set up the services

=cut

sub setup_services_for {
    my ($record_obj) = @_;

    if ( !$> ) {
        die 'This code may not be run as root.';
    }

    my ( $email_ok, $ftp_ok, $webdisk_ok );

    eval {
        $email_ok   = setup_email_if_needed($record_obj);
        $ftp_ok     = setup_ftp_if_needed($record_obj);
        $webdisk_ok = setup_webdisk_if_needed($record_obj);
    };
    if ( my $exception = $@ ) {
        delete_email_if_needed($record_obj)   if $email_ok;
        delete_ftp_if_needed($record_obj)     if $ftp_ok;
        delete_webdisk_if_needed($record_obj) if $webdisk_ok;
        die $exception;
    }

    return 1;
}

=head2 delete_services_for(RECORD)

Based on the services marked as B<enabled> in the provided object, this function deletes any
service accounts.

B<Important note>: Even though this is an act of deletion, it operates on services that are
marked B<enabled> in the object. That's because we want a reference to know which services
need any action taken at all.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub delete_services_for {
    my ($record_obj) = @_;

    if ( !$> ) {
        die 'This code may not be run as root.';
    }

    delete_email_if_needed($record_obj);
    delete_ftp_if_needed($record_obj);
    delete_webdisk_if_needed($record_obj);

    return 1;
}

=head2 setup_email_if_needed(RECORD)

Creates an email service account and the needed annotation on the subaccount linking that service account to the subaccount.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub setup_email_if_needed {
    my ($record_obj) = @_;

    if ( !eval { $record_obj->isa('Cpanel::UserManager::Record') } ) {
        require Carp;
        Carp::confess( sprintf( 'Needed a Cpanel::UserManager::Record object, but got %s instead.', ref($record_obj) ) );    # Developer-only error that indicates a bug in the code; do not translate
    }

    if ( $record_obj->has_service('email') ) {
        _password_check($record_obj);
        require Cpanel::API;
        my $result = Cpanel::API::execute(
            'Email',
            'add_pop',
            {
                email              => $record_obj->username,
                domain             => $record_obj->domain,
                password_hash      => $record_obj->password_hash,
                quota              => $record_obj->services->{email}{quota},
                send_welcome_email => $record_obj->services->{email}{send_welcome_email} // 0,
            }
        );

        if ( $result->status ) {

            if ( $record_obj->has_invite && $record_obj->services->{email}{send_welcome_email} ) {
                Cpanel::API::execute(
                    'Email',
                    'dispatch_client_settings',
                    {
                        account => $record_obj->username . '@' . $record_obj->domain,
                        to      => $record_obj->alternate_email,
                    }
                );
            }

            my $annotation = Cpanel::UserManager::Annotation->new(
                {
                    service    => 'email',
                    owner_guid => $record_obj->guid,
                    username   => $record_obj->username,
                    domain     => $record_obj->domain,
                    merged     => 1,                       # because this service account was created specifically to be part of a sub-account
                }
            );
            Cpanel::UserManager::Storage::store($annotation);
            return 1;
        }
        else {
            die join "\n", @{ $result->errors || [] };
        }
    }
    return 1;
}

=head2 delete_email_if_needed(RECORD)

Deletes an email service account and the related annotation on the subaccount that the service account is linked too.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub delete_email_if_needed {
    my ($record_obj) = @_;
    if ( $record_obj->has_service('email') ) {
        Cpanel::UserManager::Storage::delete_annotation( $record_obj, 'email' );
        require Cpanel::API;
        Cpanel::API::execute(
            'Email',
            'delete_pop',
            {
                email  => $record_obj->username,
                domain => $record_obj->domain,
            }
        );
    }
    return;
}

=head2 setup_ftp_if_needed(RECORD)

Creates an ftp service account and the needed annotation on the subaccount linking that service account to the subaccount.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub setup_ftp_if_needed {
    my ($record_obj) = @_;

    if ( !eval { $record_obj->isa('Cpanel::UserManager::Record') } ) {
        require Carp;
        Carp::confess( sprintf( 'Needed a Cpanel::UserManager::Record object, but got %s instead.', ref($record_obj) ) );    # Developer-only error that indicates a bug in the code; do not translate
    }

    if ( $record_obj->has_service('ftp') ) {
        _password_check($record_obj);
        require Cpanel::API;
        my $result = Cpanel::API::execute(
            'Ftp',
            'add_ftp',
            {
                user        => $record_obj->username,
                pass_hash   => $record_obj->password_hash,
                domain      => $record_obj->domain,
                homedir     => $record_obj->services->{ftp}{homedir},
                quota       => $record_obj->services->{ftp}{quota},
                disallowdot => 0,
            }
        );

        if ( $result->status ) {

            my $annotation = Cpanel::UserManager::Annotation->new(
                {
                    service         => 'ftp',
                    owner_guid      => $record_obj->guid,
                    username        => $record_obj->username,
                    domain          => $record_obj->domain,
                    merged          => 1,                       # because this service account was created specifically to be part of a sub-account
                    synced_password => 1,                       # because this service account was given the same password as the sub-account
                }
            );
            Cpanel::UserManager::Storage::store($annotation);
            return 1;
        }
        else {
            die join "\n", @{ $result->errors || [] };
        }
    }
    return 1;
}

=head2 delete_ftp_if_needed(RECORD)

Deletes an ftp service account and the related annotation on the subaccount that the service account is linked too.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub delete_ftp_if_needed {
    my ($record_obj) = @_;
    if ( $record_obj->has_service('ftp') ) {
        Cpanel::UserManager::Storage::delete_annotation( $record_obj, 'ftp' );
        require Cpanel::API;
        Cpanel::API::execute(
            'Ftp',
            'delete_ftp',
            {
                user    => $record_obj->username,
                domain  => $record_obj->domain,
                destroy => 0,                       # don't delete the files
            }
        );
    }
    return;
}

=head2 setup_webdisk_if_needed(RECORD)

Creates an webdisk service account and the needed annotation on the subaccount linking that service account to the subaccount.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub setup_webdisk_if_needed {
    my ($record_obj) = @_;

    local %Cpanel::CPERROR;
    local $Cpanel::context = 'webdisk';

    if ( $record_obj->has_service('webdisk') ) {
        _password_check($record_obj);

        if ( $record_obj->services->{webdisk}{enabledigest} && !$record_obj->digest_auth_hash ) {
            die lh()->maketext('You tried to enable Digest Authentication, but this account does not have a Digest Authentication hash. You must set the password for the account in order to generate a Digest Authentication hash.') . "\n";
        }

        require Cpanel::WebDisk;
        my $dataref = Cpanel::WebDisk::api2_addwebdisk(
            user             => $record_obj->username,
            domain           => $record_obj->domain,
            password_hash    => $record_obj->password_hash,
            digest_auth_hash => $record_obj->digest_auth_hash,
            homedir          => $record_obj->services->{webdisk}{homedir},
            private          => $record_obj->services->{webdisk}{private},
            perms            => $record_obj->services->{webdisk}{perms},
            enabledigest     => $record_obj->services->{webdisk}{enabledigest},
        );

        if ( 'ARRAY' eq ref $dataref && 'HASH' eq ref $dataref->[0] && !$Cpanel::CPERROR{$Cpanel::context} ) {
            my $annotation = Cpanel::UserManager::Annotation->new(
                {
                    service    => 'webdisk',
                    owner_guid => $record_obj->guid,
                    username   => $record_obj->username,
                    domain     => $record_obj->domain,
                    merged     => 1,                       # because this service account was created specifically to be part of a sub-account
                }
            );
            Cpanel::UserManager::Storage::store($annotation);
        }
        else {
            die $Cpanel::CPERROR{$Cpanel::context} || lh()->maketext('The system could not create the [asis,Web Disk] account.') . "\n";
        }
    }
    return 1;
}

=head2 delete_webdisk_if_needed(RECORD)

Deletes an webdisk service account and the related annotation on the subaccount that the service account is linked too.

=head3 Arguments

- RECORD - A Cpanel::UserManager::Record object -

=cut

sub delete_webdisk_if_needed {
    my ($record_obj) = @_;
    if ( $record_obj->has_service('webdisk') ) {
        Cpanel::UserManager::Storage::delete_annotation( $record_obj, 'webdisk' );
        require Cpanel::API;
        Cpanel::API::execute(
            'WebDisk',
            'delete_user',
            {
                user => $record_obj->full_username,
            }
        );
    }
    return;
}

# Given two record objects, one representing the "before" state and one the "after"
# state, determine whether any service settings (Email, FTP, or Web Disk) have been
# changed. If so, make the necessary adjustments.
# - For email, the only supported adjustment is changing the password and quota.
# - For FTP and Web Disk, all changes are supported.
#
# The process that should be followed for each service S is:
#   IF the new record has S
#     IF the old record also has S
#       Perform any necessary setting changes. This may be done by individually
#       modifying the settings or by deleting and re-creating the account.
#     ELSE
#       Enable service
#   ELSE IF the old record has S (even though the new one doesn't)
#     Disable service
#   ELSE
#     Don't care (remains disabled)
sub adjust_services_for {
    my ( $old_record_obj, $new_record_obj ) = @_;
    my $adjusted = 0;

    if ( $new_record_obj->has_service('email') ) {
        if ( $old_record_obj->has_service('email') ) {
            if ( !_same( $new_record_obj->services->{email}{quota}, $old_record_obj->services->{email}{quota} ) ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'Email',
                    'edit_pop_quota',
                    {
                        email  => $new_record_obj->username,
                        domain => $new_record_obj->domain,
                        quota  => $new_record_obj->services->{email}{quota},
                    }
                );
                $adjusted++;
            }
            if ( $new_record_obj->password ) {    # If the password is set, then we must be changing it. It couldn't have been loaded from disk.
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'Email',
                    'passwd_pop',
                    {
                        email    => $new_record_obj->username,
                        domain   => $new_record_obj->domain,
                        password => $new_record_obj->password,
                    }
                );
                $adjusted++;
            }
        }
        else {
            setup_email_if_needed($new_record_obj);
        }
    }
    elsif ( $old_record_obj->has_service('email') ) {
        delete_email_if_needed($old_record_obj);    # pass old object because this function expects the thing to be listed as enabled
    }

    if ( $new_record_obj->has_service('ftp') ) {
        if ( $old_record_obj->has_service('ftp') ) {
            if ( !_same( $new_record_obj->services->{ftp}{quota}, $old_record_obj->services->{ftp}{quota} ) ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'Ftp',
                    'set_quota',
                    {
                        user   => $new_record_obj->username,
                        domain => $new_record_obj->domain,
                        quota  => $new_record_obj->services->{ftp}{quota},
                    }
                );
                $adjusted++;
            }

            if ( !_same( $new_record_obj->services->{ftp}{homedir}, $old_record_obj->services->{ftp}{homedir} ) ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'Ftp',
                    'set_homedir',
                    {
                        user    => $new_record_obj->username,
                        domain  => $new_record_obj->domain,
                        homedir => $new_record_obj->services->{ftp}{homedir},
                    }
                );
                $adjusted++;
            }

            if ( $new_record_obj->password ) {    # If the password is set, then we must be changing it. It couldn't have been loaded from disk.
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'Ftp', 'passwd',
                    {
                        user   => $new_record_obj->username,
                        domain => $new_record_obj->domain,
                        pass   => $new_record_obj->password,
                    }
                );
                $adjusted++;
            }
        }
        else {
            setup_ftp_if_needed($new_record_obj);
        }
    }
    elsif ( $old_record_obj->has_service('ftp') ) {
        delete_ftp_if_needed($old_record_obj);    # pass old object because this function expects the thing to be listed as enabled
    }

    if ( $new_record_obj->has_service('webdisk') ) {
        if ( $old_record_obj->has_service('webdisk') ) {
            if (   !_same( $new_record_obj->services->{webdisk}{homedir}, $old_record_obj->services->{webdisk}{homedir} )
                || !_same( $new_record_obj->services->{webdisk}{private}, $old_record_obj->services->{webdisk}{private} ) ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'WebDisk',
                    'set_homedir',
                    {
                        user    => $new_record_obj->full_username,
                        domain  => $new_record_obj->domain,
                        homedir => $new_record_obj->services->{webdisk}{homedir},
                        private => $new_record_obj->services->{webdisk}{private},
                    }
                );
                $adjusted++;
            }

            if ( !_same( $new_record_obj->services->{webdisk}{perms}, $old_record_obj->services->{webdisk}{perms} ) ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'WebDisk',
                    'set_permissions',
                    {
                        user  => $new_record_obj->full_username,
                        perms => $new_record_obj->services->{webdisk}{perms},
                    }
                );
                $adjusted++;
            }

            # If the password is set, then this one case takes care of everything related to
            # the password AND digest auth. That means the two enabledigest conditions below
            # this one can be skipped.
            if ( $new_record_obj->password ) {
                require Cpanel::API;
                Cpanel::API::execute_or_die(
                    'WebDisk',
                    'set_password',
                    {
                        user         => $new_record_obj->full_username,
                        password     => $new_record_obj->password,
                        enabledigest => $new_record_obj->services->{webdisk}{enabledigest},
                    }
                );
                $adjusted++;
            }
            elsif ( $new_record_obj->services->{webdisk}{enabledigest} && !$old_record_obj->services->{webdisk}{enabledigest} ) {
                delete_webdisk_if_needed($old_record_obj);
                setup_webdisk_if_needed($new_record_obj);
                $adjusted++;
            }
            elsif ( !$new_record_obj->services->{webdisk}{enabledigest} && $old_record_obj->services->{webdisk}{enabledigest} ) {
                require Cpanel::WebDisk;
                Cpanel::WebDisk::api2_set_digest_auth( login => $new_record_obj->full_username, enabledigest => 0 );
                $adjusted++;
            }
        }
        else {
            setup_webdisk_if_needed($new_record_obj);
        }
    }
    elsif ( $old_record_obj->has_service('webdisk') ) {
        delete_webdisk_if_needed($old_record_obj);    # pass old object because this function expects the thing to be listed as enabled
    }

    return $adjusted;
}

# If the password has not been changed since the sub-account was upgraded from a service account (if it was),
# then it only has a temporary password set, and this isn't useful for creating new service accounts.
# Force the end-user to change the password (which will set synced_password) before they are allowed to
# enable services.
sub _password_check {
    my ($record_obj) = @_;
    if ( !$record_obj->synced_password ) {
        die lh()->maketext('You must reset the password for this account before you can edit any services.') . "\n";
    }
    return;
}

# A string equality check that also treats undef as equal to undef, but undef as not equal to a defined value.
sub _same {
    my ( $first, $second ) = @_;
    return ( !defined($first) && !defined($second) ) || ( defined($first) && defined($second) && $first eq $second );
}

1;
