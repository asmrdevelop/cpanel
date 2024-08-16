package Cpanel::Email::Maildir::Utils;

# cpanel - Cpanel/Email/Maildir/Utils.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule             ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::PwCache                ();
use Cpanel::FileUtils::Dir         ();
use Cpanel::Exception              ();
use Cpanel::Email::Mailbox         ();
use Cpanel::Context                ();
use Cpanel::FileUtils::Dir         ();

sub get_maildir_users_under_dir {
    Cpanel::Context::must_be_list();

    return if !-d $_[0];

    return grep { ( index( $_, '.' ) != 0 && -d "$_[0]/$_/cur" ) ? 1 : 0 } @{ Cpanel::FileUtils::Dir::get_directory_nodes( $_[0] ) };

}

sub purge_maildir {
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
    my @dirs;

    foreach my $node ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($maildir) } ) {
        next if ( $node !~ m{^\.} );
        my $full_path = "$maildir/$node";
        next if -l $full_path;
        if ( -d "$full_path/cur" && -d "$full_path/new" && -d "$full_path/tmp" ) {
            push @dirs, $full_path;
        }
    }

    foreach my $path ( "$maildir/cur", "$maildir/new", "$maildir/tmp" ) {
        if ( -d $path ) {
            push @dirs, $path;
        }
    }

    require File::Path;
    return File::Path::remove_tree( @dirs, { 'verbose' => $verbose } );

}

sub get_relative_dirs_to_create {
    my %dirs_to_create;
    for my $maildir (qw(cur new tmp)) {
        $dirs_to_create{$maildir} = 1;
        for my $folder ( 'Drafts', 'Sent', 'Trash', 'Junk' ) {
            @dirs_to_create{ ( ".$folder", ".$folder/$maildir" ) } = ( 1, 1 );
        }
    }
    my @dirs = sort keys %dirs_to_create;
    return @dirs;
}

sub get_users_email_accounts_with_maildir {
    my ($user) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new($user);
    my $homedir    = Cpanel::PwCache::gethomedir($user);

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);

    my $primary_domain = $cpuser_ref->{'DOMAIN'};

    my @accounts;
    if ( Cpanel::Email::Mailbox::looks_like_maildir("$homedir/mail") ) { push @accounts, '_mainaccount@' . $primary_domain }

    foreach my $domain ( $primary_domain, @{ $cpuser_ref->{'DOMAINS'} } ) {
        push @accounts, map { $_ . '@' . $domain } get_maildir_users_under_dir("$homedir/mail/$domain");
    }

    return \@accounts;
}

sub create_symlink_to_subaccount {
    my ( $user, $email_account ) = @_;

    my $src = _get_maildir_symlink_path( $user, $email_account );
    my ( $login, $domain ) = split m<\@>, $email_account, 2;
    my $dest = "$domain/$login";

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    my $privs = Cpanel::AccessIds::ReducedPrivileges->new($user);

    symlink( $dest, $src ) or do {
        my $err = $!;
        if ( !$!{'EEXIST'} ) {
            warn "Failed to create symbolic link “$src” -> “$dest”: $!";
        }
        $! = $err;

        return 0;
    };

    return 1;
}

sub remove_symlink_to_subaccount {
    my ( $user, $email_account ) = @_;

    my $location = _get_maildir_symlink_path( $user, $email_account );

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    my $privs = Cpanel::AccessIds::ReducedPrivileges->new($user);

    unlink($location) or do {
        my $err = $!;
        if ( !$!{'ENOENT'} ) {
            warn "Failed to remove symbolic link “$location”: $!";
        }
        $! = $err;
        return 0;
    };

    return 1;
}

sub _get_maildir_symlink_path {

    my ( $user, $email_account ) = @_;

    my $homedir = Cpanel::PwCache::gethomedir($user);
    my ( $login, $domain ) = split m<\@>, $email_account, 2;

    #It would be ideal if this logic were in an object so this misuse
    #wouldn’t even be possible...
    if ( $login eq '_mainaccount' ) {
        die "No symlink for system user accounts! ($email_account)";
    }

    my $udomain = ( $domain =~ tr<.><_>r );

    return "$homedir/mail/.$login\@$udomain";
}

1;
