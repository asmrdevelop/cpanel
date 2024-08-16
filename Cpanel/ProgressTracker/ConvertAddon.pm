package Cpanel::ProgressTracker::ConvertAddon;

# cpanel - Cpanel/ProgressTracker/ConvertAddon.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

sub new {
    my ( $class, $opts_hr ) = @_;
    if ( !( $opts_hr && 'HASH' eq ref $opts_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }
    _validate_required_params($opts_hr);

    my $db_obj = _get_db_obj();
    my $self   = bless {
        'job_id' => $db_obj->start_job($opts_hr),
        'db_obj' => $db_obj,
    }, $class;
    return $self;
}

sub finish_job {
    my $self = shift;
    $self->{'db_obj'}->finish_job( { 'job_id' => $self->{'job_id'} } );
    return 1;
}

sub fail_job {
    my $self = shift;
    $self->{'db_obj'}->fail_job( { 'job_id' => $self->{'job_id'} } );
    return 1;
}

sub start_step {
    my ( $self, $step_name ) = @_;
    $self->{'db_obj'}->start_step_for_job( { 'job_id' => $self->{'job_id'}, 'step_name' => $step_name } );
    return 1;
}

sub fail_step {
    my ( $self, $step_name ) = @_;
    $self->{'db_obj'}->fail_step_for_job( { 'job_id' => $self->{'job_id'}, 'step_name' => $step_name } );
    return 1;
}

sub finish_step {
    my ( $self, $step_name ) = @_;
    $self->{'db_obj'}->finish_step_for_job( { 'job_id' => $self->{'job_id'}, 'step_name' => $step_name } );
    return 1;
}

sub set_warnings_for_step {
    my ( $self, $step_name, $warnings_ar ) = @_;
    $self->{'db_obj'}->set_step_warnings_for_job( { 'job_id' => $self->{'job_id'}, 'step_name' => $step_name, 'warnings' => join "\n", @{$warnings_ar} } );
    return 1;
}

sub _get_db_obj {
    Cpanel::LoadModule::load_perl_module('Cpanel::ProgressTracker::ConvertAddon::DB');
    return Cpanel::ProgressTracker::ConvertAddon::DB->new();
}

sub _validate_required_params {
    my $opts = shift;

    my @exceptions;
    foreach my $required_arg (qw(domain source_acct target_acct)) {
        push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] ) if !defined $opts->{$required_arg};
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
