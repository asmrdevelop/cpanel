# cpanel - Whostmgr/Accounts/Modify/MultiAccountModification.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Accounts::Modify::MultiAccountModification;

use cPstrict;

use Whostmgr::ACLS ();

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Modify::MultiAccountModification - Accessor object for tracking modify account variables when modifying multiple accounts

=head1 SYNOPSIS

    use Whostmgr::Accounts::Modify::MultiAccountModification ();

    my $modification = Whostmgr::Accounts::Modify::MultiAccountModification->new( );

=head1 DESCRIPTION

This class is utilized in Whostmgr::Accounts::Modify to track the various flags and settings
that need to be passed between the various operations to modify several accounts with the same
options.

=head1 ACCESSORS

=over

=item calling_user_has_root

Whether or not the user performing the modify operation possessess root privileges.

=item messages

A list of info-level messages logged during the account modification.

=item needs_apache_restart

Whether or not Apache needs to be restarted as a result of the account modification.

=item needs_phpfpm_rebuild_files

Whether or not the PHP configs for the user’s vhosts need to be rebuilt as a result of a username
or domain name change.

=item needs_rebuild_etc_cache_files

Whether or not the /etc cache files need to be updated via updateuserdomains as a result of the
account modification.

=item needs_rebuild_domain_ips

Whether or not dedicated IPs and their dependencies need to be rebuilt as a result of the account
modification.

=item needs_rebuild_firewall

Whether or not the system firewall configuration needs to be rebuilt as a result of the account
modification.

=item warnings

A list of warn-level messages logged during the account modification.

=back

=cut

use Class::XSAccessor {
    accessors => [
        qw(
          calling_user_has_root
          messages
          needs_apache_restart
          needs_rebuild_etc_cache_files
          needs_rebuild_domain_ips
          needs_rebuild_firewall
          warnings
        )
    ]
};

=head2 Whostmgr::Accounts::Modify::MultiAccountModification->new()

Creates a new object.

=over

=item Input

=over

This function takes no input parameters.

=back

=item Output

=over

Returns the new object.

=back

=back

=cut

sub new ($class) {
    return bless {
        calling_user_has_root => Whostmgr::ACLS::hasroot(),
        messages              => [],
        warnings              => [],
    }, $class;
}

=head2 $obj->add_messages( @messages )

Adds additional messages to the message list, stripping any messages that are whitespace only.

=over

=item Input

=over

A list of messages to add to the messages list.

=back

=item Output

=over

This function has no output.

=back

=back

=cut

sub add_messages ( $self, @msgs ) {
    push @{ $self->messages() }, grep { $_ && !/^\s*$/ } @msgs;
    return;
}

=head2 $obj->add_warnings( @messages )

Adds additional warnings to the warnings list, stripping any warnings that are whitespace only.

=over

=item Input

=over

A list of warnings to add to the warnings list.

=back

=item Output

=over

This function has no output.

=back

=back

=cut

sub add_warnings ( $self, @warnings ) {
    push @{ $self->warnings() }, grep { $_ && !/^\s*$/ } @warnings;
    return;
}

1;
