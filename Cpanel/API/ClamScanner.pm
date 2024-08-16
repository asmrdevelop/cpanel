# cpanel - Cpanel/API/ClamScanner.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::API::ClamScanner;

use cPstrict;

use Cpanel::Imports;
use Cpanel::ClamScanner ();

=head1 MODULE

C<Cpanel::API::ClamScanner>

=head1 DESCRIPTION

C<Cpanel::API::ClamScanner> provides UAPI methods for querying and
managing the ClamScanner application

=head1 FUNCTIONS

=head2 get_scan_status()

Gets the current status of any current ClamAV scan for specified user

=head3 ARGUMENTS

None

=head3 RETURNS

Array of information about the current or last scan.

The returned data will contain a structure similar to the JSON below:

  "data" : {
     "total_file_size" : 3640159,
     "total_file_count" : 133,
     "infected_files" : [],
     "file" : "/home/user/last-file-scanned.txt",
     "scanned_file_size" : 36401,
     "scan_complete" : 1,
     "time_started" : 1608300445,
     "scanned_file_count" : 133
  }

=cut

sub get_scan_status ( $args, $result ) {

    my $status = Cpanel::ClamScanner->new()->get_scan_status();

    $result->data( $status->{'contents'} );
    $result->message( $status->{'message'} );

    return 1;
}

=head2 start_scan()

Start a ClamAV scan on a specified user's home directory

=head3 ARGUMENTS

None

=head3 RETURNS

None

=cut

sub start_scan ( $args, $result ) {

    my $scan_type = $args->get_length_required('scan_type');
    my $scanner   = Cpanel::ClamScanner->new( 'skip_role_checks' => 1 );

    $result->data( $scanner->scan_files($scan_type) );

    return 1;
}

=head2 get_scan_paths()

Retrieve the available ClamAV scan types.

=head3 ARGUMENTS

None

=head3 RETURNS

Array of available scan types, similar to the following:

 "data" : [
    {
       "id" : "home",
       "message" : "Scan Entire Home Directory"
    },
    {
       "message" : "Scan Mail",
       "id" : "mail"
    },
    {
       "id" : "public_ftp",
       "message" : "Scan Public FTP Space"
    },
    {
       "message" : "Scan Public Web Space",
       "id" : "public_html"
    }
 ],

=cut

sub get_scan_paths ( $args, $result ) {
    my %path_messages = (
        mail        => locale()->maketext('Scan Mail'),
        home        => locale()->maketext('Scan Entire Home Directory'),
        public_html => locale()->maketext('Scan Public Web Space'),
        public_ftp  => locale()->maketext('Scan Public FTP Space'),
    );

    my @list;
    my $scan_types = Cpanel::ClamScanner::get_scan_types();
    for my $type ( @{ $scan_types || [] } ) {
        push @list, {
            id      => $type,
            message => $path_messages{$type} || do {
                warn "Unknown scan path type '$type'\n";    # Developer message; do not translate
                $type;
            },
        };
    }
    $result->data( \@list );
    return 1;
}

=head2 disinfect_files(actions => { file1 => 'delete', file2 => 'quarantine' })

See /usr/local/cpanel/Cpanel/API/ClamScanner-disinfect_files.openapi.yaml for more details.

=cut

sub disinfect_files ( $args, $result ) {

    my $actions = $args->get('actions');

    require Cpanel::JSON;
    require Cpanel::UserTasks;
    require Cpanel::ClamScanner;

    Cpanel::ClamScanner::validate_disinfect_actions($actions);
    Cpanel::ClamScanner::disinfection_queued();

    my $ut = Cpanel::UserTasks->new();

    my $task_id = $ut->add(
        subsystem => 'ClamScanner',
        action    => 'disinfect',
        args      => {
            actions => scalar( Cpanel::JSON::Dump($actions) ),
        },
    );
    my $task = $ut->get($task_id);

    if ( !$task ) {
        $result->raw_error( locale()->maketext('The system failed to add the disinfection task to the queue.') );
        return;
    }
    else {
        Cpanel::ClamScanner::finish_disinfection();
    }

    $result->data(
        {
            task_id => $task_id,
            log     => Cpanel::ClamScanner::disinfection_log_path(),
        }
    );

    return 1;
}

=head2 check_disinfection_status(last_id => ...)

See /usr/local/cpanel/Cpanel/API/ClamScanner-check_disinfection_status.openapi.yaml for details

=cut

sub check_disinfection_status ( $args, $result ) {

    require Cpanel::ClamScanner;

    my $last_id = $args->get('last_id') || undef;
    my $log     = Cpanel::ClamScanner::load_disinfection_log($last_id);

    my $data = {
        details => $log,
        log     => Cpanel::ClamScanner::disinfection_log_path(),
    };

    if ( !@$log ) {

        # There are three possible states here
        #  none - Nothing is queued to run
        #  queued - There is a queued disinfection
        #  running - There is a running disinfection, but it has not yet written any log entries.
        $data->{status} = Cpanel::ClamScanner::get_disinfection_state();
    }
    else {
        my $last_entry = $log->[-1];
        $data->{status} = $last_entry->{type} && $last_entry->{type} eq 'done' ? 'done' : 'running';
    }

    $result->data($data);
    return 1;

}

use constant FEATURE => 'clamavconnector_scan';

=head2 list_infected_files()

Return a list of information for infected files on the system.

=head3 ARGUMENTS

None

=head3 RETURNS

Array of hashes containing information on infected files.

The returned data will contain a structure similar to the JSON below:

  "data" : [
      {
          "file": "/path/to/file",
          "virus_type": "Eicar-Signature"
      },
      {
          "file": "/path/to/another/file",
          "virus_type": "Eicar-Signature"
      }
  ]

=cut

sub list_infected_files ( $args, $result ) {

    my $list_infected_files = Cpanel::ClamScanner->new()->list_infected_files();

    $result->data( $list_infected_files->{'data'} );
    $result->raw_warning( $list_infected_files->{'warning'} );

    return 1;
}

# We specifically do not specify any worker node or server role preferences because we do not currently
# support ClamAV execution on worker nodes. To implement this functionality, we will need
# to ensure the prerequisite that ClamAV is installed on the worker and solve the problem
# of merging results from both the parent and child. In addition, the current implementation
# of automatic UAPI forwarding will only run on the parent or child node and not both.
my $clamscanner_scan = {
    needs_feature => FEATURE,
    allow_demo    => 0
};

our %API = (
    check_disinfection_status => $clamscanner_scan,
    disinfect_files           => {
        %$clamscanner_scan,
        requires_json => 1,
    },
    get_scan_status     => $clamscanner_scan,
    get_scan_paths      => $clamscanner_scan,
    list_infected_files => $clamscanner_scan,
    start_scan          => $clamscanner_scan,
);

1;
