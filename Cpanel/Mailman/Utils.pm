package Cpanel::Mailman::Utils;

# cpanel - Cpanel/Mailman/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles                  ();
use Cpanel::Context                      ();
use Cpanel::JSON                         ();
use Cpanel::Mailman::Filesys             ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Validate::FilesystemNodeName ();

#Pass in list IDs as: "${listname}_${domain}"
sub get_cpanel_mailmancfg {
    my (@list_ids) = @_;

    if ( @list_ids > 1 ) {
        Cpanel::Context::must_be_list('multiple lists passed');
    }

    #In scalar context, we want to return the first item in the list
    #rather than the number of elements in the list.
    return ( map { $_ ? Cpanel::JSON::Load($_) : undef } get_cpanel_mailmancfg_json(@list_ids) )[ 0 .. $#list_ids ];
}

sub get_cpanel_mailmancfg_json {
    my (@list_ids) = @_;

    if ( @list_ids > 1 ) {
        Cpanel::Context::must_be_list('multiple lists passed');
    }

    for (@list_ids) {
        if ( !Cpanel::Validate::FilesystemNodeName::is_valid($_) ) {
            my $list_id_as_text = $_ // 'UNDEFINED';
            die "Invalid list ID: “$list_id_as_text”";
        }
    }

    my @pickle_files = map { Cpanel::Mailman::Filesys::get_list_dir($_) . '/config.pck' } @list_ids;

    my $run = Cpanel::SafeRun::Object->new(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/bin/dump_cpanel_mailmancfg_as_json",
        args    => [
            join( ',', @pickle_files ),
            'mailman',
        ],
    );
    die $run->autopsy() if $run->CHILD_ERROR();

    #This particular script doesn't actually give an error code if,
    #for example, there is a permissions error; instead, it just writes to
    #stderr and happily returns a 0 status.
    die $run->stderr() if $run->stderr();

    #In scalar context, we want to return the first item in the list
    #rather than the number of elements in the list.
    return ( split m<\n>, $run->stdout() )[ 0 .. $#list_ids ];
}

1;
