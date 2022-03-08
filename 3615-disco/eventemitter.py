import inspect

class EventEmitter:
    def __init__(self, log=False):
        self._eventshandlers = {}
        self._doLog = log

    def trigger(self, eventname, args=None):
        if self._doLog:
            print("event:", eventname, "/ args:", args)

        if '*' in self._eventshandlers:
            for clbk in self._eventshandlers['*']:
                clbk(eventname, args)

        if eventname in self._eventshandlers:
            for clbk in self._eventshandlers[eventname]:
                if len(inspect.getfullargspec(clbk).args) > 0: 
                    clbk(args)
                else: 
                    clbk()

    def on(self, eventname, handler=None):
        if not type(eventname) is list:
                eventname = [eventname]
        def registerhandler(handler):
            for e in eventname:
                if e in self._eventshandlers:
                    self._eventshandlers[e].append(handler)
                else:
                    self._eventshandlers[e] = [handler]
            return handler
        if handler: registerhandler(handler)    # direct call object.on("event", do)
        else: return registerhandler            # decorator call @object.on("event")


'''
Usage exemple:

ee = EventEmitter()

@ee.on("foo")
def foo():
    print("This is foo's first handler")

@ee.on("bar")
def bar():
    print("This is bar's first handler")

@ee.on("foo")
def foobar(x):
    print("This is foo's second handler with arg",x)

ee.on("bar", lambda x: print("This is bar's second handler, with arg", x))

ee.trigger("bar", "yo")
ee.trigger("foo", [1234])

'''