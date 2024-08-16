package Whostmgr::Transfers::SystemsBase::userdataBase;

# cpanel - Whostmgr/Transfers/SystemsBase/userdataBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base module. See one of its subclasses to do real work.
#----------------------------------------------------------------------

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings)

use Cpanel::ArrayFunc                    ();
use Cpanel::Locale                       ();
use Cpanel::Exception                    ();
use Cpanel::DataStore                    ();
use Cpanel::Validate::FilesystemNodeName ();

use Try::Tiny;

our $MAX_USERDATA_SIZE = 1024**2 * 32;    # 32 MEG

use base qw(
  Whostmgr::Transfers::Systems
);

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

# This returns success, undef if the userdata file is missing
sub read_extracted_userdata_for_domain {
    my ( $self, $domain ) = @_;

    my $err;
    try {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($domain);
    }
    catch {
        $err = $_;
    };
    return ( 0, Cpanel::Exception::get_string($err) )
      if $err;

    my ( $ok, $userdata_dir ) = $self->find_extracted_userdata_dir();
    return ( 0, $userdata_dir ) if !$ok;

    if ( !$userdata_dir ) {
        return ( 0, _locale()->maketext( 'This archive does not contain a “[_1]” directory.', 'userdata' ) );
    }

    my $userdata_file = "$userdata_dir/$domain";
    return ( 1, undef ) if !-f $userdata_file;

    if ( ( stat(_) )[7] > $MAX_USERDATA_SIZE ) {
        return ( 0, _locale()->maketext( 'The userdata file, “[_1]” could not be loaded because it exceeds the maximum size of “[_2]” bytes.', $userdata_file, $MAX_USERDATA_SIZE ) );
    }

    local ( $!, $@ );
    my $payload = Cpanel::DataStore::load_ref($userdata_file) or do {
        return ( 0, "The system failed to load the file “$userdata_file”." );
    };

    _prune_userdata_contents($payload);

    return ( 1, $payload );
}

sub _prune_userdata_contents ($payload) {

    # This mirrors the deletion of this information from the cpuser file
    # in Whostmgr::Transfers::Utils.
    delete $payload->{'proxy_backend'};

    return;
}

sub find_extracted_userdata_dir {
    my ($self) = @_;

    if ( !$self->{'_userdata_dir'} ) {
        my $extractdir = $self->extractdir();

        my $olduser = $self->olduser();    # case 113733: Used only to find the files

        my $dir = Cpanel::ArrayFunc::first(
            sub { -d },
            map { "$extractdir/$_" } (
                "userdata/$olduser",
                'userdata',
            )
        );

        if ( !$dir ) {
            return ( 0, _locale()->maketext( 'The system could not locate the “[_1]” directory in the extracted archive.', 'userdata' ) );
        }
        $self->{'_userdata_dir'} = $dir;
    }

    return ( 1, $self->{'_userdata_dir'} );
}

1;
