package Cpanel::MultiUserDirStore::VirtualUser;

# cpanel - Cpanel/MultiUserDirStore/VirtualUser.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::LoadModule                   ();

use parent 'Cpanel::MultiUserDirStore';

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $param (qw(virtual_user domain service)) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', [$param] ) if !$OPTS{$param};
    }

    for my $param_value ( @OPTS{qw(virtual_user domain service)} ) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($param_value);
    }

    return $class->SUPER::new(%OPTS);
}

sub _init_path {
    my ( $class, %OPTS ) = @_;

    my ( $dir, $user, $subdir, $virtual_user, $domain, $service ) = @OPTS{qw( dir user subdir virtual_user domain service )};

    if ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => q{} } ) ne $user ) {
        die Cpanel::Exception::create( 'DomainOwnership', 'The account “[_1]” does not own the domain “[_2]”.', [ $user, $domain ] );
    }

    # TODO: Modify this check to be service aware
    Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Lookup::MailUser::Exists');
    if ( !Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist("$virtual_user\@$domain") ) {
        die Cpanel::Exception::create( 'UserNotFound', 'The account “[_1]” does not own the email account “[_2]”.', [ $user, "$virtual_user\@$domain" ] );
    }

    my $user_dir = "$dir/$user";
    my $path     = "$user_dir/$domain/$service/$virtual_user/$subdir";
    for my $current_path ( "$user_dir/$domain", "$user_dir/$domain/$service", "$user_dir/$domain/$service/$virtual_user", $path ) {
        next if -d $current_path;
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $current_path, 0755 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $current_path, error => $! ] );
    }

    return $path;
}

1;
