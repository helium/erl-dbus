#ifndef EBUS_OBJECT_H
#define EBUS_OBJECT_H

#include "ebus_connection.h"
#include "ebus_shared.h"

typedef struct
{
    ErlNifPid pid;
    void *    user;
} dbus_object;


void
ebus_object_load(ErlNifEnv * env);

dbus_object *
mk_dbus_object_resource(ErlNifEnv * env, ErlNifPid * pid, void * user_resource);


//
// Connection object callbacks
//

void
cb_object_unregister(DBusConnection * connection, void * data);


DBusHandlerResult
cb_object_handle_message(DBusConnection * connection, DBusMessage * message, void * data);

void
cb_object_handle_reply(DBusPendingCall * pending, void * data);

#endif /* EBUS_OBJECT_H */
