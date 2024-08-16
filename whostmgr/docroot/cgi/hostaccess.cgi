#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/hostaccess.cgi     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Form            ();
use Cpanel::OS              ();
use Whostmgr::ACLS          ();
use Whostmgr::HTMLInterface ();

if ( !check_acls('all') ) {
    html_error( 403, "Forbidden" );
    require Cpanel::Exit;
    Cpanel::Exit::exit_with_stdout_closed_first();
}

my %FORM = Cpanel::Form::parseform();
if ( $FORM{'add_nftables_rule'} ) {
    eval {
        require Cpanel::XTables;
        my $obj = Cpanel::XTables->new(
            'chain' => 'cPanel-HostAccessControl',
        );
        if ( !$obj->table_exists( 'name' => 'filter', 'family' => 'inet' ) ) {
            my $create_line = [ [qw'add table inet filter'] ];
            $obj->exec_checked_calls($create_line);
        }
        $obj->init_chain() if !$obj->chain_exists();
        $obj->add_rule(
            'port'     => $FORM{'port'},
            'ip'       => $FORM{'ip'},
            'protocol' => $FORM{'protocol'},
            'action'   => $FORM{'action'},
        );
    };
    if ($@) {
        html_error( 500, $@ );
        require Cpanel::Exit;
        Cpanel::Exit::exit_with_stdout_closed_first();
    }

    $FORM{'no_cache'} = 1;
}
elsif ( $FORM{'delete_nftables_rule'} ) {
    require Cpanel::XTables;
    Cpanel::XTables->new(
        'chain' => 'cPanel-HostAccessControl',
    )->delete_rule(
        'handle' => $FORM{'delete_nftables_rule'},
    );
    $FORM{'no_cache'} = 1;
}
if ( $FORM{'fetch_nftables_rules'} ) {
    my $rules = [];
    eval {
        require Cpanel::JSON;
        require Cpanel::XTables;
        my $obj = Cpanel::XTables->new( 'chain' => 'cPanel-HostAccessControl' );
        $obj->clear_ruleset_cache();
        $rules = $obj->get_rules;
    };
    if ($@) {
        push @$rules, { 'error' => $@ };
        print "Status: 500\r\nContent-type: application/json\r\n\r\n";
    }
    else {
        print "Status: 200\r\nContent-type: application/json\r\n\r\n";
    }
    print Cpanel::JSON::pretty_dump($rules);
    require Cpanel::Exit;
    Cpanel::Exit::exit_with_stdout_closed_first();
}

print "Content-type: text/html\r\n\r\n";
do_main();

sub do_main {
    require Cpanel::Template;
    my $saved;
    if ( exists $FORM{'save_accesslist'} ) {
        $saved = savehostaccesslist();
    }

    if ( Cpanel::OS::supports_hostaccess() ) {

        require Cpanel::HostAccessLib;
        my $hostaccesslib = Cpanel::HostAccessLib->new;

        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => 'host_access/hostaccess.tmpl',
                'data'          => {
                    'action'    => q{},
                    'saved'     => $saved,
                    'services'  => $hostaccesslib->fetch_services(),
                    'actions'   => $hostaccesslib->fetch_actions(),
                    'wildcards' => $hostaccesslib->fetch_wildcards(),
                    'rules'     => $hostaccesslib->{'DB'},
                    'emptyrule' => {
                        'daemon_list' => [],
                        'client_list' => [],
                        'action_list' => [],
                        'comment'     => '',
                        'type'        => 'empty_action',
                    },
                },
            },
        );
    }
    else {

        # Host Access Controls not supported on CentOS 8+, so we
        # have a different implementation based on nftables.
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => 'host_access/nftables_access.tmpl',
                'data'          => {
                    'no_cache' => $FORM{'no_cache'} || 0,
                },
            },
        );
    }
    return;
}

sub savehostaccesslist {
    require Cpanel::HostAccessLib;
    my $hostaccesslib = Cpanel::HostAccessLib->new;
    for ( my $i = 0; $i <= $#{ $hostaccesslib->{'DB'} }; $i++ ) {
        ${ $hostaccesslib->{'DB'} }[$i]->{'linenum'} = ( $i + 1 );
        foreach my $list ( 'daemon_list', 'action_list', 'client_list' ) {
            if ( defined ${ $hostaccesslib->{'DB'} }[$i]->{$list} ) {
                ${ $hostaccesslib->{'DB'} }[$i]->{$list} = [];
            }
        }
    }

    foreach my $key ( keys %FORM ) {
        my $evalue = $FORM{$key};
        my ( $slinenum, $element ) = split( /-/, $key, 2 );

        next if ( !defined $slinenum || $slinenum !~ /^\d+$/ || !defined $element );

        my $linenum = int $slinenum;
        $linenum--;

        my ( $keyname, $keynum ) = split( /_/, $element, 2 );

        if ( $keyname eq 'daemon' ) {
            ${ $hostaccesslib->{'DB'} }[$linenum]->{'daemon_list'} = Cpanel::HostAccessLib::daemon_parse($evalue);
        }
        elsif ( $keyname eq 'client' ) {
            ${ $hostaccesslib->{'DB'} }[$linenum]->{'client_list'} = Cpanel::HostAccessLib::client_parse($evalue);
        }
        elsif ( $keyname eq 'action' ) {
            my $newval = Cpanel::HostAccessLib::ptrim($evalue);
            next if ( $newval eq '' );
            ${ ${ $hostaccesslib->{'DB'} }[$linenum]->{'action_list'} }[$keynum] = $newval;
        }
        elsif ( $keyname eq 'comment' ) {
            ${ $hostaccesslib->{'DB'} }[$linenum]->{'comment'} = $evalue;
        }
    }
    foreach my $line ( split( /:/, $FORM{'eventlist'} ) ) {
        my ( $linenum, $offset ) = split( /,/, $line );
        foreach ( my $i = 0; $i <= $#{ $hostaccesslib->{'DB'} }; $i++ ) {
            if ( ${ $hostaccesslib->{'DB'} }[$i]->{'linenum'} == $linenum ) {
                my $newpt = ( $i + $offset );
                my @nl    = splice( @{ $hostaccesslib->{'DB'} }, $i, 1 );
                splice( @{ $hostaccesslib->{'DB'} }, $newpt, 0, @nl );
                last;
            }
        }
    }
    for ( my $i = 0; $i <= $#{ $hostaccesslib->{'DB'} }; $i++ ) {
        foreach my $list ( 'daemon_list', 'action_list', 'client_list' ) {
            if ( !defined ${ $hostaccesslib->{'DB'} }[$i]->{$list} ) {
                ${ $hostaccesslib->{'DB'} }[$i]->{$list} = [];
            }
        }
        if ( !defined ${ $hostaccesslib->{'DB'} }[$i]->{'type'} ) {
            ${ $hostaccesslib->{'DB'} }[$i]->{'type'} = 'access_list';
        }
    }
    $hostaccesslib->reserialize();
    $hostaccesslib->commit();

    return 1;
}

sub check_acls {
    my @acls = @_;
    Whostmgr::ACLS::init_acls();
    return scalar( grep { Whostmgr::ACLS::checkacl($_) } @acls ) == scalar(@acls);
}

sub html_error {
    my ( $code, $msg ) = @_;
    print "Status: $code\r\nContent-type: text/html\r\n\r\n";
    Whostmgr::HTMLInterface::defheader();
    print "<h1>$msg</h1>";
    Whostmgr::HTMLInterface::sendfooter();
    return;
}
