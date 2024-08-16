package Whostmgr::Transfers::ConvertAddon::MigrateData::PasswdAccounts;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/PasswdAccounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use Cpanel::Exception ();
use Cpanel::PwCache   ();

sub copy {
    my ( $self, $opts_hr ) = @_;

    if ( !( $opts_hr && ref $opts_hr eq 'HASH' ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }
    _validate_required_params($opts_hr);

    $self->_copy_users( $opts_hr->{'domain'}, $opts_hr->{'docroot'} );

    return 1;
}

# Must be defined in subclasses.
sub _copy_users;

sub _copy_valid_users {
    my ( $self, $domain, $docroot, $new_docroot, $passwd_src, $passwd_dst, $shadow_src, $shadow_dst ) = @_;

    my %copied_accts;
    my ( @skipped_accts, @missing_homedir, @conflict_accts );

    while ( my $line = readline $passwd_src ) {
        my ( $user, $pass, $uid, $gid, $owner, $directory, $shell, @extra ) = split /:/, $line;
        if ( $user =~ m/\@\Q$domain\E$/ ) {

            # Do not move FTP accounts that match 'to_cpanel_username@addon-domain.tld', as it will causing conflicting entries (See CPANEL-10194)
            if ( $self->isa('Whostmgr::Transfers::ConvertAddon::MigrateData::FTPAccounts') && $user =~ m/\A\Q$self->{'to_username'}\E\@\Q$domain\E$/ ) {
                push @conflict_accts, $user;
            }
            elsif ( $directory =~ m/^\Q$docroot\E(?:\/|$)/ ) {

                # Ensure the account is configured to use a directory within the docroot of the addon domain
                # we need to update the directory to point to the new account's docroot
                $directory =~ s/^\Q$docroot\E/$new_docroot/;

                my ( $to_user_uid, $to_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'to_username'} ) )[ 2, 3 ];
                print                  {$passwd_dst} join( ':', $user, $pass, $to_user_uid, $to_user_gid, $self->{'to_username'}, $directory, $shell, @extra );
                push @missing_homedir, { user => $user, directory => $directory } if !-d $directory;
                $copied_accts{$user} = 1;
            }
            else {
                push @skipped_accts, $user;
            }
        }
    }

    if ($shadow_src) {
        while ( my $line = readline $shadow_src ) {
            my ( $user, $other ) = split /:/, $line, 2;
            print {$shadow_dst} "$user:$other" if $copied_accts{$user};
        }
    }

    return \@skipped_accts, \@missing_homedir, \@conflict_accts;
}

sub _validate_required_params {
    my $opts = shift;

    my @exceptions;
    foreach my $required_arg (qw(domain docroot)) {
        if ( not defined $opts->{$required_arg} ) {
            push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] );
        }
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
