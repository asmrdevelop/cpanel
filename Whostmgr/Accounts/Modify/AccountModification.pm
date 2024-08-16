# cpanel - Whostmgr/Accounts/Modify/AccountModification.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Accounts::Modify::AccountModification;

use cPstrict;

use Cpanel::Config::CpUser::Object      ();
use Cpanel::LinkedNode::Worker::GetAll  ();
use Cpanel::LinkedNode::Worker::Storage ();

use parent 'Whostmgr::Accounts::Modify::MultiAccountModification';

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Modify::AccountModification - Accessor object for tracking modify account variables

=head1 SYNOPSIS

    use Whostmgr::Accounts::Modify::AccountModification;

    my $modification = Whostmgr::Accounts::Modify::AccountModification->new( user => 'username' );

=head1 DESCRIPTION

This class is utilized in Whostmgr::Accounts::Modify to track the various flags and settings
that need to be passed between the various operations to modify an account.

=head1 ACCESSORS

=over

=item changed_contact_email

Whether or not the user’s contact email addresses have been changed. Used to determine whether the
user’s contact info needs to be updated.

=item changed_domain

Whether or not the user’s domain name has been changed. Differs from L<changing_domainname> in
that this flag is only set after the domain name change has been applied. Used to determine whether
the Passenger apps and email hold/suspension files need to be updated.

=item changed_hascgi

Whether or not the user’s CGI setting has been changed. Used to determine whether or not the vhosts
for the user’s domains need to be updated.

=item changed_package

Whether or not the user’s package related settings changed as a result of the modification. Used
to determine whether or not the /etc cache files need to be updated via updateuserdomains.

=item changed_shell

Whether or not the user’s shell has been changed. Used to determine whether or not the user’s shell
needs to be updated in the passwd files and potentially queues Apache updates and restart.

=item changed_theme

Whether or not the user’s cPanel theme has been changed. Used to determine whether or not cpsrvd
gets signaled to reload for the user being modified.

=item changed_user

Whether or not the user’s username has been changed. Differs from L<changing_username> in that
this flag is only set after the username change has been applied. Used to determine whether or not
the vhosts for the user’s domains, Passenger apps, email hold/suspension files and the port
authority database need to be updated.

=item changing_domainname

Whether or not the user’s domain name is going to be changed. Differs from L<changed_domain> in
that this flag is set if the input options indicate that a domain name change has been requested
(but not necesarrily processed successfully). Used to determine whether or not a domain name
change should be attempted and to setup SSL for the new domain name.

=item changing_mail_node

Whether or not the user’s mail node is going to be changed. Used to determine whether or not we
need to queue a background task to offload the user’s mail from the current server to the newly
specified server.

=item changing_username

Whether or not the user’s username is going to be changed. Differs from L<changed_user> in that
this flag is set if the input options indicate that a username change has been requested (but not
necessarily processed successfully). Used to determine whether or not a username change should be
attempted.

=item cpconf

A convenience HASHREF containing the config values from C</var/cpanel/cpanel.conf>.

=item cpuser_data

A convenience L<Cpanel::Config::CpUser::Object> instance containing the user’s
settings from their user file in C</var/cpanel/users>.

=item decoded_email

If the C<contactemail> option is provided, this contains the first email address specified decoded
and validated.

=item decoded_email_2

If the C<contactemail> option is provided, this contains the second email address specified decoded
and validated.

=item domain

If the C<domain> option is provided this contains the new domain name for the user. If the option
is not provided, this defaults to the C<DOMAIN> value from the cpuser data.

=item fpm_restore_config_hr

If the user’s domain is being renamed this will contain a HASHREF of PHP configs (if any) to be
restored after the domain name change has been processed.

=item is_reseller

Whether or not the user being modified is currently a reseller. Used to determine whether or not
reseller-specific setup or teardown needs to be processed.

=item mail_node_alias

The linked mail node to assign this user’s mail services to.

=item new_owner

If the C<OWNER> or C<owner> option is provided this will contain the username of the new owner of
the account. If these options are not provided this will contain the current owner of the account.

=item new_shell

If the C<HASSHELL> or C<shell> option is provided this will contain the new shell for the user
suitable for being written to a passwd file. If these options are not provided this value will be
undefined.

=item new_shell_display

A friendly display value for the user’s shell. If the C<HASSHELL> or C<shell> options are not
provided this will default to “unmodified”.

=item new_theme

If the C<RS> or C<CPTHEME> option is provided this will contain the new theme for the user. If
these options are not provided this value will be set to the user’s current theme.

=item new_user

If the C<newuser> option is provided this will contain the new username for the account. If the
option is not provided this will contain the current username of the account.

=item old_dkim

The value of the C<HASDKIM> configuration setting in the cpuser file prior to the account
modification. Used to determine whether or not the DKIM keys for the user’s domains need to be
setup or torn down.

=item old_domain

If the domain name is changed via the C<domain> option, after the domain name change is processed
this will contain the old domain name. Used to update the email suspend/hold files with the new
domain name.

=item old_spf

The value of the C<HASSPF> configuration setting in the cpuser file prior to the account
modification. Used to determine whether or not the SPF DNS records for the user’s domains need
to be updated or removed.

=item rename_database_objects

Whether or not to rename the user’s database objects. This can be supplied as an option but is
only available to root-level users.

=item user

The username of the account being modified. This value is required and must be passed to the
constructor.

=back

=cut

use Class::XSAccessor {
    accessors => [
        qw(
          changed_contact_email
          changed_domain
          changed_hascgi
          changed_package
          changed_shell
          changed_theme
          changed_user
          changing_domainname
          changing_mail_node
          changing_username
          cpconf
          cpuser_data
          decoded_email
          decoded_email_2
          domain
          fpm_restore_config_hr
          is_reseller
          mail_node_alias
          needs_phpfpm_rebuild_files
          new_owner
          new_shell
          new_shell_display
          new_theme
          new_user
          old_dkim
          old_domain
          old_spf
          rename_database_objects
          renaming_domain
          user
        )
    ]
};

=head2 Whostmgr::Accounts::Modify::AccountModification->new()

Creates a new object.

=over

=item Input

=over

This object requires a C<user> parameter.

Optionally, C<cpuser_data> and C<cpconf> HASHREFs can also be supplied specifying
the user data and cPanel config.

If C<cpuser_data> or C<cpconf> are not supplied, they will be loaded as part of the
constructor.

=back

=item Output

=over

Returns the new object.

=back

=back

=cut

sub new ( $class, %opts ) {

    my $user = $opts{user};
    if ( !$user ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ name => "user" ] );
    }

    my $cpuser_data = $opts{cpuser_data};
    if ( !$cpuser_data ) {
        require Cpanel::Config::LoadCpUserFile;
        $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    }

    my $cpconf = $opts{cpconf};
    if ( !$cpconf ) {
        require Cpanel::Config::LoadCpConf;
        $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    }

    my $self = $class->SUPER::new();

    @{$self}{qw(user cpuser_data cpconf)} = ( $user, $cpuser_data, $cpconf );

    return bless $self, $class;
}

=head2 $obj->get_extended_output()

Gets the extended output that modify account returns.

=over

=item Input

=over

This function takes no input values.

=back

=item Output

=over

Returns a HASHREF of values describing the modify account operation.

=over

=item user

The username the modify account operation was applied to. If the username
is changed as part of the operation this is the new username.

=item domain

The primary domain of the user being modified. If the primary domain was changed
as part of the operation this is the new domain.

=item cpuser

The final cPanel user data after the account has been modified.

=item setshell

The new shell for the user as a result of the modification. Will be set to
“unmodified’ if the shell is not changed during the modification.

=back

=back

=back

=cut

sub get_extended_output ($self) {

    my %cpuser = %{ $self->cpuser_data() };

    # Scrub the WORKER_NODE entries from the user data that we return
    # Failure to do so will expose API tokens in the return data
    for my $worker_type ( Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES() ) {
        Cpanel::LinkedNode::Worker::Storage::unset(
            \%cpuser,
            $worker_type,
        );
    }

    return {
        user     => $self->new_user(),
        domain   => $self->domain(),
        cpuser   => Cpanel::Config::CpUser::Object->adopt( \%cpuser ),
        setshell => $self->new_shell_display(),
    };
}

1;
