package Cpanel::Email::Maildir::Link;

# cpanel - Cpanel/Email/Maildir/Link.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::FileUtils::Dir               ();
use Cpanel::AccessIds::ReducedPrivileges ();

# Cpanel::Email::Maildir::Utils can also setup symlinks, however it
# does it per account instead of per domain or per user

=pod

=encoding utf-8

=head1 NAME

Cpanel::Email::Maildir::Link - Tools for creating and removing symlink from the main account
to sub email accounts

=head1 SYNOPSIS

  my $pw = [Cpanel::PwCache::getpwnam('bob')];

  Cpanel::Email::Maildir::Link::remove_maildir_symlinks_for_users_domain( $pw, $olddomain );
  Cpanel::Email::Maildir::Link::setup_maildir_symlinks_for_users_domain( $pw, $domain );
  Cpanel::Email::Maildir::Link::setup_all_maildir_symlinks_for_user($pw);
  Cpanel::Email::Maildir::Link::remove_all_maildir_symlinks_for_user($pw);


=head1 DESCRIPTION

This module provides functionality to setup and remove symlinks
from the users main account to the virtual email accounts.

The symlinks allow the main account to access email under the subaccess
INBOX by accessing a folder in the format USER@DOMAIN_TLD in their
accout.

=head1 METHODS

=head2 setup_all_maildir_symlinks_for_user( PW_REF )

Setup all symlinks for maildir for all virtual users
that belong to the user in PW_REF

=head3 Arguments

Required:

  PW_REF          - An array ref returned from Cpanel::PwCache::getpw* or getpw*

=head3 Return Value

  1 - Success

=head3 Failure

This function may generate exceptions on failure.

=cut

sub setup_all_maildir_symlinks_for_user {
    my ($pwref) = @_;
    die "Implementor Error: setup_all_maildir_symlinks_for_user requires a getpw* arrayref" if ref $pwref ne 'ARRAY';
    my ( $uid, $gid, $homedir ) = @{$pwref}[ 2, 3, 7 ];
    my $privs   = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    my @domains = _get_mail_domains_in_homedir($homedir);

    foreach my $domain (@domains) {
        _setup_maildir_symlinks_for_domain( $homedir, $domain );
    }
    return 1;
}

=head2 setup_maildir_symlinks_for_users_domain( PW_REF, DOMAIN )

Setup symlinks for maildir for all virtual users
that belong to the user in PW_REF domain.

=head3 Arguments

Required:

  PW_REF          - An array ref returned from Cpanel::PwCache::getpw* or getpw*
  DOMAIN          - The domain to setup.

=head3 Return Value

  1 - Success

=head3 Failure

This function may generate exceptions on failure.

=cut

sub setup_maildir_symlinks_for_users_domain {
    my ( $pwref, $domain ) = @_;
    die "Implementor Error: setup_maildir_symlinks_for_users_domain requires a getpw* arrayref" if ref $pwref ne 'ARRAY';
    die "Implementor Error: setup_maildir_symlinks_for_users_domain requires a domain"          if !length $domain;
    my ( $uid, $gid, $homedir ) = @{$pwref}[ 2, 3, 7 ];
    my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );

    return _setup_maildir_symlinks_for_domain( $homedir, $domain );

}

=head2 remove_all_maildir_symlinks_for_user( PW_REF )

Remove all symlinks for maildir for all virtual users
that belong to the user in PW_REF

=head3 Arguments

Required:

  PW_REF          - An array ref returned from Cpanel::PwCache::getpw* or getpw*

=head3 Return Value

  1 - Success

=head3 Failure

This function may generate exceptions on failure.

=cut

sub remove_all_maildir_symlinks_for_user {
    my ($pwref) = @_;
    die "Implementor Error: remove_all_maildir_symlinks_for_user requires a getpw* arrayref" if ref $pwref ne 'ARRAY';
    my ( $uid, $gid, $homedir ) = @{$pwref}[ 2, 3, 7 ];
    my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );

    my @domains = _get_mail_domains_in_homedir($homedir);
    foreach my $domain (@domains) {
        _remove_maildir_symlinks_for_domain( $homedir, $domain );
    }
    return 1;
}

=head2 remove_maildir_symlinks_for_users_domain( PW_REF, DOMAIN )

Remove symlinks for maildir for all virtual users
that belong to the user in PW_REF domain.

=head3 Arguments

Required:

  PW_REF          - An array ref returned from Cpanel::PwCache::getpw* or getpw*
  DOMAIN          - The domain to setup.

=head3 Return Value

  1 - Success

=head3 Failure

This function may generate exceptions on failure.

=cut

sub remove_maildir_symlinks_for_users_domain {
    my ( $pwref, $domain ) = @_;
    die "Implementor Error: remove_maildir_symlinks_for_users_domain requires a getpw* arrayref" if ref $pwref ne 'ARRAY';
    die "Implementor Error: remove_maildir_symlinks_for_users_domain requires a domain"          if !length $domain;
    my ( $uid, $gid, $homedir ) = @{$pwref}[ 2, 3, 7 ];
    my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    return _remove_maildir_symlinks_for_domain( $homedir, $domain );
}

sub _setup_maildir_symlinks_for_domain {
    my ( $homedir, $domain ) = @_;

    my $linkdomain = ( $domain =~ tr<.><_>r );
    if ( opendir( my $maildomain_dir_fh, "$homedir/mail/$domain" ) ) {
        while ( my $acct = readdir($maildomain_dir_fh) ) {
            next if ( $acct =~ /^\./
                || $acct =~ /^new$|^cur$|^tmp$|^INBOX$|^dbox-Mails$|^dovecot|^subscriptions$|^maildirfolder$|^maildirsize$/
                || !-e "$homedir/mail/$domain/$acct/cur" );    # only link if its maildir (skip mdbox)
            my $linkname = "${acct}\@${linkdomain}";
            if ( !-l "$homedir/mail/.${linkname}" ) {
                symlink( "$domain/$acct", "$homedir/mail/.${linkname}" );
            }
        }
        close($maildomain_dir_fh);
    }
    return 1;
}

sub _remove_maildir_symlinks_for_domain {
    my ( $homedir, $domain ) = @_;

    my $linkdomain = ( $domain =~ tr<.><_>r );
    my $nodes_ar   = eval { Cpanel::FileUtils::Dir::get_directory_nodes("$homedir/mail"); };
    my @links;
    if ($nodes_ar) {
        @links = map { "$homedir/mail/$_" } grep ( m{\@\Q$linkdomain\E$}, @{$nodes_ar} );
    }

    return 0 if !@links;

    return unlink @links;
}

sub _get_mail_domains_in_homedir {
    my ($homedir) = @_;
    my $nodes_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes("$homedir/mail"); };
    if ($nodes_ar) {
        return grep { $_ =~ tr{.}{} && substr( $_, 0, 1 ) ne '.' && !m/^new$|^cur$|^tmp$|^INBOX$|^dbox-Mails$|^dovecot|^subscriptions$|^maildirfolder$|^maildirsize$/ } @{$nodes_ar};
    }
    return ();
}

1;
