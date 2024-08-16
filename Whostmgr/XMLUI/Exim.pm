package Whostmgr::XMLUI::Exim;

# cpanel - Whostmgr/XMLUI/Exim.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::Exim         ();
use Whostmgr::Exim::Config ();
use Whostmgr::ApiHandler   ();

sub remove_messages_mail_queue {
    my ( $status, $statusmsg, $data ) = Whostmgr::Exim::remove_messages_mail_queue(@_);
    return Whostmgr::ApiHandler::out( { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data }, RootName => 'remove_message_mail_queue', NoAttr => 1 );
}

sub deliver_messages_mail_queue {
    my ( $status, $statusmsg, $data ) = Whostmgr::Exim::deliver_messages_mail_queue(@_);
    return Whostmgr::ApiHandler::out( { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data }, RootName => 'deliver_message_mail_queue', NoAttr => 1 );
}

sub unfreeze_messages_mail_queue {
    my ( $status, $statusmsg, $data ) = Whostmgr::Exim::unfreeze_messages_mail_queue(@_);
    return Whostmgr::ApiHandler::out( { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data }, RootName => 'unfreeze_message_mail_queue', NoAttr => 1 );
}

sub deliver_mail_queue {
    my ( $status, $statusmsg, $data ) = Whostmgr::Exim::deliver_mail_queue(@_);
    return Whostmgr::ApiHandler::out( { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data }, RootName => 'deliver_mail_queue', NoAttr => 1 );
}

sub purge_mail_queue {
    my ( $status, $statusmsg, $data ) = Whostmgr::Exim::purge_mail_queue(@_);
    return Whostmgr::ApiHandler::out( { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data }, RootName => 'purge_mail_queue', NoAttr => 1 );
}

sub validate_exim_configuration_syntax {
    return Whostmgr::ApiHandler::out(
        Whostmgr::Exim::validate_exim_configuration_syntax(@_),
        'RootName' => 'validate_exim_configuration_syntax', 'NoAttr' => 1
    );
}

sub validate_current_installed_exim_config {
    my ( $status, $statusmsg, $html ) = Whostmgr::Exim::Config::validate_current_installed_exim_config(@_);
    return Whostmgr::ApiHandler::out(
        { 'status' => $status, 'statusmsg', $statusmsg, 'html' => $html },
        'RootName' => 'validate_current_installed_exim_config', 'NoAttr' => 1
    );
}

sub exim_configuration_check {
    my ( $status, $statusmsg, $message ) = Whostmgr::Exim::Config::configuration_check(@_);
    return Whostmgr::ApiHandler::out(
        { 'status' => $status, 'statusmsg', $statusmsg, 'message' => $message },
        'RootName' => 'exim_configuration_check', 'NoAttr' => 1
    );
}

sub remove_in_progress_exim_config_edit {
    my ( $status, $statusmsg, $message ) = Whostmgr::Exim::Config::remove_in_progress_exim_config_edit(@_);
    return Whostmgr::ApiHandler::out(
        { 'status' => $status, 'statusmsg', $statusmsg },
        'RootName' => 'remove_in_progress_exim_config_edit', 'NoAttr' => 1
    );
}

1;
