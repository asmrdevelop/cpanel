package Cpanel::Admin::Modules::Cpanel::cpuser;

# cpanel - Cpanel/Admin/Modules/Cpanel/cpuser.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::cpuser - Set cpuser values

=head1 SYNOPSIS

    use Cpanel::AdminBin::Call ();

    Cpanel::AdminBin::Call::call( 'Cpanel', 'cpuser', 'SET', $key => $value );

=head1 DESCRIPTION

This module provides a generic facility for user processes to request
static updates to the user’s cpuser datastore.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::CpUserGuard            ();
use Cpanel::Config::LoadCpConf             ();
use Cpanel::Config::CpUser::Object::Update ();
use Cpanel::LoadModule                     ();
use Cpanel::Exception                      ();

sub _actions {
    return (
        'SET',
        'SET_CONTACT_EMAIL_ADDRESSES',
        'SET_TEAM_CONTACT_EMAIL_ADDRESSES',
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 SET( $KEY, $VALUE )

This function sets $VALUE for $KEY in the caller’s cpuser datastore.

NB: Before a value can be accepted it’s necessary that validation logic
for that value exist.

=cut

sub SET ( $self, $key, $value ) {
    my $validator_cr = $self->can("_validate_$key");

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            my $validator_cr = $key !~ tr<A-Z_><>c;
            $validator_cr &&= $self->can("_validate_$key");

            if ( !$validator_cr ) {
                die _invalidparamerr("bad key: $key");
            }

            # The validator will probably require() in one or more modules.
            local ( $@, $! );

            if ( !defined $value ) {
                die _invalidparamerr("Undefined “$key”!");
            }

            if ( $value =~ tr<\0\x0a=><> || !$validator_cr->($value) ) {
                die _invalidparamerr("Invalid “$key”: “$value”");
            }
        },
    );

    my $cp = Cpanel::Config::CpUserGuard->new( $self->get_caller_username() );
    $cp->{'data'}{$key} = $value;
    $cp->save();

    return;
}

=head2 SET_CONTACT_EMAIL_ADDRESSES( $PASSWORD, \@OLD_ADDRS, \@NEW_ADDRS )

A variant of C<SET()> specifically for contact email addresses.

Contact email addresses get their own function here because an attacker who
can overwrite these effectively takes over the account. To guard against that
this requires the caller to re-authenticate as part of the call. That
re-authentication goes through cphulkd and so guards against brute-force
attacks.

As an additional race-safety measure, this also requires submission of
the account’s old contact email addresses.

Nothing is returned. The following exceptions can be thrown:

=over

=item * L<Cpanel::Exception::WrongAuthentication>, if $PASSWORD is wrong

=item * L<Cpanel::Exception::RateLimited>, if the password check
is rate-limited

=item * … or whatever L<Cpanel::ContactInfo::Email::Write>’s C<for_cpuser()>
might throw.

=back

=cut

sub SET_CONTACT_EMAIL_ADDRESSES ( $self, $pw, $old_addrs_ar, $new_addrs_ar ) {    ## no critic qw(ManyArgs)

    my $guard = Cpanel::Config::CpUserGuard->new( $self->get_caller_username() );

    $self->_set_contact_email(
        $guard,
        $old_addrs_ar,
        $new_addrs_ar,
        sub {
            $self->whitelist_exceptions(
                [
                    'Cpanel::Exception::RateLimited',
                ],
                sub {
                    require Cpanel::Passwd::CheckAsRoot;

                    my $cphulk_context = _cphulk_context();

                    if ( !Cpanel::Passwd::CheckAsRoot::is_correct( $self->get_caller_username(), $pw, $cphulk_context ) ) {
                        die Cpanel::Exception::create_raw( 'WrongAuthentication', 'wrong password' );
                    }
                },
            );
        },
    );

    return;
}

sub SET_TEAM_CONTACT_EMAIL_ADDRESSES ( $self, $pw, $old_addrs_ar, $new_addrs_ar ) {    ## no critic qw(ManyArgs)

    $self->_set_team_contact_email(
        $old_addrs_ar,
        $new_addrs_ar,
        sub {
            $self->whitelist_exceptions(
                [
                    'Cpanel::Exception::RateLimited',
                ],
                sub {
                    require Cpanel::Passwd::CheckAsRoot;

                    my $team_username = "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}";

                    if ( !Cpanel::Passwd::CheckAsRoot::is_correct_team_user( $team_username, $pw ) ) {
                        die Cpanel::Exception::create_raw( 'WrongAuthentication', 'wrong password' );
                    }
                },
            );
        },
    );

    return;
}

sub _set_contact_email ( $self, $guard, $old_addrs_ar, $new_addrs_ar, $before_cr = undef ) {    ## no critic qw(ManyArg)

    $self->cpuser_has_at_least_one_of_features_or_die(
        'updatecontact', 'updatenotificationprefs',
    );

    # Avoid undef warnings:
    $_ //= q<> for ( @$new_addrs_ar, @$old_addrs_ar );

    $self->whitelist_exceptions(
        [
            'Cpanel::Exception::InvalidParameter',
        ],
        sub {
            $before_cr->() if $before_cr;

            Cpanel::Config::CpUser::Object::Update::set_contact_emails(
                $guard->{'data'},
                $old_addrs_ar,
                $new_addrs_ar,
            );
        },
    );

    $guard->save();

    $self->_notify_email_changes( $old_addrs_ar, $new_addrs_ar );

    return;
}

sub _set_team_contact_email ( $self, $old_addrs_ar, $new_addrs_ar, $password_check_cr = undef ) {    ## no critic qw(ManyArg)

    $self->cpuser_has_at_least_one_of_features_or_die(
        'updatecontact', 'updatenotificationprefs',
    );

    # Avoid undef warnings:
    $_ //= q<> for ( @$new_addrs_ar, @$old_addrs_ar );

    $self->whitelist_exceptions(
        [
            'Cpanel::Exception::InvalidParameter',
        ],
        sub {
            $password_check_cr->() if $password_check_cr;

            # team user request to empty secondary email
            if ( @$new_addrs_ar == 1 ) {
                push @$new_addrs_ar, '';
            }
            Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config');
            my $team_obj = Cpanel::Team::Config->new( $self->get_caller_username() );
            $team_obj->set_contact_email( $ENV{'TEAM_USER'}, $new_addrs_ar );
        },
    );

    $self->_notify_email_changes( $old_addrs_ar, $new_addrs_ar );

    return;
}

sub _notify_email_changes ( $self, $old_addrs_ar, $new_addrs_ar ) {    ## no critic qw(ManyArg)
    require Cpanel::ContactInfo::Notify;
    require Cpanel::IP::Remote;
    my $to_user = defined $ENV{'TEAM_USER'} ? "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}" : $self->get_caller_username();

    Cpanel::ContactInfo::Notify::send_contactinfo_change_notifications_to_user(
        to_user          => $to_user,
        username         => $self->get_caller_username(),
        origin           => 'cpanel',
        ip               => Cpanel::IP::Remote::get_current_remote_ip(),
        notifications_hr => {
            CONTACTEMAIL => {
                current_value => $old_addrs_ar->[0],
                new_value     => $new_addrs_ar->[0],
            },
            CONTACTEMAIL2 => {
                current_value => $old_addrs_ar->[1],
                new_value     => $new_addrs_ar->[1],
            },
        },
    );

    return;
}

sub _cphulk_context {
    my $module = __PACKAGE__     =~ s<.+::><>r;
    my $func   = ( caller 1 )[3] =~ s<.+::><>r;
    return "admin-$module-$func";
}

#----------------------------------------------------------------------

sub _invalidparamerr ($str) {
    return Cpanel::Exception::create_raw( 'InvalidParameter', $str );
}

#----------------------------------------------------------------------
# Validators MUST return truthy to indicate a pass.
# They can also throw errors to indicate specific validation failures.
#
# Note that at least 1 test uses this internal interface.

sub _validate_SSL_DEFAULT_KEY_TYPE ($type) {

    return 1 if $type eq 'system';

    require Cpanel::SSL::DefaultKey;
    return 1 if Cpanel::SSL::DefaultKey::is_valid_value($type);

    return;
}

1;
