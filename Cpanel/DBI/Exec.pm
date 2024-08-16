package Cpanel::DBI::Exec;

# cpanel - Cpanel/DBI/Exec.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A mix-in class. Do not call or instantiate directly.
#----------------------------------------------------------------------

use strict;

use DBI         ();
use Cpanel::DBI ();    # PPI USE OK -- perlcc

use base qw(Cpanel::DBI::db DBI::db);    #help out perlcc

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

#Returns the temp object and the temp file path.
sub _write_temp_file {
    my ( $self, $contents ) = @_;

    die 'List context only!' if !wantarray;

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
    Cpanel::LoadModule::load_perl_module('Cpanel::TempFile');

    #Reduce privs here (if needed) so that later when we fork,
    #the setuid'd user can read this file.
    my $privs = $self->_need_to_reduce_privs() && Cpanel::AccessIds::ReducedPrivileges->new( $self->_root_should_exec_as_this_user() );

    local $!;

    my $temp_obj = Cpanel::TempFile->new();
    my ( $pwfile, $pwfile_fh ) = $temp_obj->file();

    print {$pwfile_fh} $contents or die Cpanel::Exception::create( 'IO::FileWriteError', [ buffer => \$contents, path => $pwfile, error => $! ] );

    close $pwfile_fh or die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $pwfile, error => $! ] );

    return ( $temp_obj, $pwfile );
}

sub _need_to_reduce_privs {
    return !$> ? 1 : 0;
}

sub _exec_program_path_hr { die 'ABSTRACT' }

#Both of the following accept the same arguments as Cpanel::SafeRun::Object.
*exec_with_credentials       = \&_exec_program_path_hr;
*exec_with_credentials_no_db = \&_exec_program_path_hr;

sub _exec_as_non_root {
    my ( $self, $saferun_args_hr ) = @_;

    my $before_exec = sub {
        if ( $saferun_args_hr->{'before_exec'} ) {
            $saferun_args_hr->{'before_exec'}->(@_);
        }

        if ( $> == 0 ) {
            my $target_user = $self->_root_should_exec_as_this_user();

            require Cpanel::PwCache;
            my $homedir = Cpanel::PwCache::gethomedir($target_user);

            require Cpanel::AccessIds::SetUids;
            Cpanel::AccessIds::SetUids::setuids($target_user);

            chdir $homedir or warn "chdir($homedir) failed: $!";
        }
    };

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
    return Cpanel::SafeRun::Object->new(
        %$saferun_args_hr,
        before_exec => $before_exec,
    );
}

1;
