package Cpanel::Email::Convert::User;

# cpanel - Cpanel/Email/Convert/User.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Quota::Temp::Object';

use Try::Tiny;
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Email::Convert::Account ();
use Cpanel::Email::Maildir::Utils   ();
use Cpanel::Email::Mdbox::Utils     ();
use Cpanel::Email::Mailbox::Set     ();

use Cpanel::Exception       ();
use Cpanel::PwCache         ();
use Cpanel::Dovecot::Config ();

=pod

=head1 NAME

Cpanel::Email::Convert::User

=head1 DESCRIPTION

This module is provides an interface to convert email
account that belong to a cpanel user between various
formats which include: mdbox, maildir, and mbox

=head1 SYNOPSIS

    Cpanel::Email::Convert::User->new(
        'system_user'   => $system_user,
        'skip_removal'  => $skip_removal,
        'target_format' => 'mdbox',
        'source_format' => 'maildir',
    )->convert_email_account($email_account);

   Cpanel::Email::Convert::User->new(
        'system_user'   => $system_user,
        'skip_removal'  => $skip_removal,
        'target_format' => 'maildir',
        'source_format' => 'mdbox',
    )->convert_all();

=cut

=head1 METHODS

=head2 new

Create a new Cpanel::Email::Convert::User that can be called
to convert a single email account (convert_email_account)
or all email accounts (convert_all) owned by a cPanel user.

=head3 Arguments

system_user    - The cPanel user that owns the email acccounts
                 that you want to convert.

skip_removal   - 0 or 1 - If 1 the source_format files will be
                 left in place after a successful conversion to
                 target_format.  This is generally not desireable
                 as it will result in duplicate disk space, but is
                 useful for doing a 'dry-run'.

source_format  - The format of the mail in the source_maildir (mbox, mdbox, maildir, or detect for auto-detection)

target_format  - The format of the mail in the target_maildir (mbox, mdbox, maildir, or detect for auto-detection)

verbose        - 0 or 1 - Print verbose messages about the conversion progress

=head3 Return Value

A Cpanel::Email::Convert::User object

=cut

sub new {
    my ( $class, %opts ) = @_;

    my $system_user = $opts{'system_user'};

    foreach my $required (qw(system_user skip_removal target_format source_format)) {
        if ( !length $opts{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    foreach my $format (qw(target_format source_format)) {
        if ( !$Cpanel::Dovecot::Config::KNOWN_FORMATS{ $opts{$format} } ) {
            die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be one of the following: [join,~, ,_2]", [ $format, [ sort keys %Cpanel::Dovecot::Config::KNOWN_FORMATS ] ] );
        }
    }

    my $self = bless {
        'original_pid'  => $$,
        'system_user'   => $system_user,
        'target_format' => $opts{'target_format'},
        'source_format' => $opts{'source_format'},
        'homedir'       => Cpanel::PwCache::gethomedir($system_user),
        'verbose'       => exists $opts{'verbose'} ? int $opts{'verbose'} : 1,
        'skip_removal'  => $opts{'skip_removal'}   ? 1                    : 0,    # skips removing old format files (ie delete maildir after successful mdbox conversion, or delete mdbox when convert fails)
    }, $class;

    if ( $self->{'skip_removal'} ) {
        print "The original unconverted files will be left in place after the conversion (double disk usage).\n";
    }
    else {
        print "The original files will be removed after the conversion.\n";
    }

    $self->lift_user_quota();

    return $self;
}

=head2 convert_email_account

Convert a single email account owned by the cPanel user
(system_user) that was passed in when the object was created
to the (target_format) that was passed in when the object was created.

=head3 Arguments

The email account to convert in the format <USER>@<DOMAIN>,
                  <SYSTEM_USER>, or _mainaccount@<DOMAIN>.

=head3 Return Value

The result of the Cpanel::Email::Convert::Account->convert function

=cut

sub convert_email_account {
    my ( $self, $email_account ) = @_;
    my $user_conf = Cpanel::Config::LoadCpUserFile::load( $self->{'system_user'} );

    # If we pass in the cpuser, we want to convert it to be _mainaccount@<CPUSER'sDOMAIN>
    # since that is the format expected by Cpanel::Email::Convert::Account
    if ( $email_account eq $self->{'system_user'} ) {
        $email_account = '_mainaccount@' . $user_conf->{'DOMAIN'};
    }
    return Cpanel::Email::Convert::Account->new( 'email_account' => $email_account, 'user_convert_obj' => $self, 'is_utf8' => $user_conf->{'UTF8MAILBOX'} ? 1 : 0 )->convert();
}

=head2 convert_all

Convert a all email accounts owned by the cPanel user
(system_user) that was passed in when the object was created
to the (target_format) that was passed in when the object was created.

If any account cannot be converted, a warning is generated but is
non-fatal

=head3 Arguments

None

=head3 Return Value

This returns an array reference of failures. Each member of the array
is itself an array reference, like:

    [ <username> => <error> ]

=cut

sub convert_all {
    my ($self) = @_;

    my @failures;

    my $accounts_ref;
    if ( $self->{'source_format'} eq 'mdbox' ) {
        $accounts_ref = Cpanel::Email::Mdbox::Utils::get_users_email_accounts_with_mdbox( $self->{'system_user'} );
    }
    elsif ( $self->{'source_format'} eq 'maildir' ) {
        $accounts_ref = Cpanel::Email::Maildir::Utils::get_users_email_accounts_with_maildir( $self->{'system_user'} );
    }
    else {
        die "The system does not know how to discover all accounts using “$self->{'source_format'}”.";
    }

    foreach my $account ( sort @{$accounts_ref} ) {
        try {
            $self->convert_email_account($account);
        }
        catch {
            push @failures, [ $account => $_ ];

            local $@ = $_;
            warn;
        };
    }

    Cpanel::Email::Mailbox::Set::set_users_mailbox_format(
        'user'   => $self->{'system_user'},
        'format' => $self->{'target_format'}
    );

    return \@failures;
}

#
# The below functions are intended to only be called by
# Cpanel::Email::Convert::Account and should not be called
# outside of that object
#
# Unpacking skipped below for speed
sub skip_removal  { return $_[0]->{'skip_removal'}; }
sub system_user   { return $_[0]->{'system_user'}; }
sub homedir       { return $_[0]->{'homedir'}; }
sub verbose       { return $_[0]->{'verbose'}; }
sub target_format { return $_[0]->{'target_format'}; }
sub source_format { return $_[0]->{'source_format'}; }
sub original_pid  { return $_[0]->{'original_pid'}; }

1;
