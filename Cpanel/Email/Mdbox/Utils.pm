package Cpanel::Email::Mdbox::Utils;

# cpanel - Cpanel/Email/Mdbox/Utils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule             ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::PwCache                ();
use Cpanel::Exception              ();
use Cpanel::Email::Mailbox         ();
use Cpanel::FileUtils::Dir         ();
use Cpanel::Context                ();

sub purge_mdbox {
    my (%opts) = @_;

    foreach my $required (qw(user maildir verbose)) {
        if ( !length $opts{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    my $user    = $opts{'user'};
    my $maildir = $opts{'maildir'};
    my $verbose = $opts{'verbose'};

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new($user);
    my @dirs       = ( "$maildir/mailboxes", "$maildir/storage" );

    require File::Path;
    return File::Path::remove_tree( @dirs, { 'verbose' => $verbose } );
}

sub get_relative_dirs_to_create {
    return (qw(mailboxes storage));
}

sub get_mdbox_users_under_dir {
    my $dir = shift;
    Cpanel::Context::must_be_list();
    return if !-d $dir;

    return grep { ( !m/^[.]+/ && -d "$dir/$_/storage" ) ? 1 : 0 } @{ Cpanel::FileUtils::Dir::get_directory_nodes($dir) };
}

sub get_users_email_accounts_with_mdbox {
    my ($user) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new($user);
    my $homedir    = Cpanel::PwCache::gethomedir($user);

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);

    my $primary_domain = $cpuser_ref->{'DOMAIN'};

    my @accounts;
    if ( Cpanel::Email::Mailbox::looks_like_mdbox("$homedir/mail") ) {
        push @accounts, "_mainaccount\@$primary_domain";
    }

    foreach my $domain ( $primary_domain, @{ $cpuser_ref->{'DOMAINS'} } ) {
        push @accounts, map { $_ . '@' . $domain } get_mdbox_users_under_dir("$homedir/mail/$domain");
    }

    return \@accounts;
}

1;
