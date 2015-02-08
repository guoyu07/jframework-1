###
    TODO:

    Make a J.ReactiveVar class which is like Meteor's ReactiveVar
    but has a bunch of functions powered by finer-grained deps like:
        general:
            equals
        numbers:
            lessThan, greaterThan, lessThanOrEq, greaterThanOrEq
        arrays:
            contains (can keep an object-set for this)
    have J.AutoVar inherit from J.ReactiveVar

###

class J.AutoVar
    constructor: (valueFunc, onChange = null, equalsFunc = J.util.equals, wrap = true) ->
        ###
            AutoVars default to being "lazy", i.e. not calculated
            until .get().

            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoVar becomes non-lazy.
        ###

        @_bindEnvironment = if Meteor.isServer then Meteor.bindEnvironment else _.identity

        unless @ instanceof J.AutoVar
            return new J.AutoVar valueFunc, onChange, equalsFunc, wrap

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless onChange is null or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "Invalid onChange argument: #{onChange}"

        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc
        @wrap = wrap

        @_var = new ReactiveVar undefined, @equalsFunc
        @_preservedValue = undefined
        @_getting = false

        @active = true
        if Tracker.active then Tracker.onInvalidate => @stop()

        @_valueComp = null
        if @onChange? then Tracker.afterFlush @_bindEnvironment =>
            if not @_valueComp?
                @_setupValueComp()

        @_arrIndexOfDeps = {} # value: dep

    _deepGet: ->
        # Reactive
        ###
            Unwrap any nested AutoVars during get(). This is because
            @valueFunc may get a performance benefit from isolating
            part of its reactive logic in an AutoVar.
        ###
        value = @_var.get()
        if value instanceof J.AutoVar then value.get() else value

    _preserve: (v) ->
        if v instanceof J.AutoDict or v instanceof J.AutoList
            v.snapshot()
        else
            v

    _recompute: ->
        console.log 'Recompute ', @tag
        oldPreservedValue = @_preservedValue
        oldValue = Tracker.nonreactive => @_deepGet()

        try
            rawValue = @valueFunc.call null, @
        catch e
            if Meteor.isClient and e is J.fetching.FETCH_IN_PROGRESS
                # This must be the first time that this var
                # is being computed, and it's premature because
                # data is currently being fetched. So we can
                # return here. We don't have to do @_var.set
                # or onChange or anything else.
                J.assert oldValue is undefined, "FIXME: Actually this can happen, but we need to handle setting back to undefined."

                if @_getting
                    # This will be caught by a top-level AutoRun like @_setupValueComp
                    # or a component's render function.
                    throw e
                else
                    return undefined

            else throw e

        if rawValue is @constructor._UNDEFINED_WITHOUT_SET
            # This is used for the AutoVars of AutoDict fields
            # that are getting deleted synchronously (ahead of
            # Tracker.flush) because they just realized that
            # keysFunc doesn't include their key.
            return undefined

        else if rawValue is undefined
            throw new Meteor.Error "#{@toString()}.valueFunc must not return undefined."

        newValue = if @wrap then J.Dict._deepReactify rawValue else rawValue

        @_var.set newValue
        @_preservedValue = @_preserve newValue

        # Check if we should fire @_arr* deps (if oldValue and newValue are arrays)
        # TODO: This fine-grained dependency stuff should be part of a J.ReactiveVar
        # class that J.AutoVar inherits from
        oldArr = null
        if oldValue instanceof J.List and oldValue.active isnt false
            oldArr = Tracker.nonreactive => oldValue.getValues()
        else if _.isArray oldValue
            oldArr = oldValue
        newArr = null
        if newValue instanceof J.List and newValue.active isnt false
            newArr = Tracker.nonreactive => newValue.getValues()
        else if _.isArray newValue
            newArr = newValue
        if oldArr? and newArr?
            for x, i in oldArr
                if newArr[i] isnt x
                    @_arrIndexOfDeps[i]?.changed()
            for y, i in newArr
                if oldArr[i] isnt y
                    @_arrIndexOfDeps[i]?.changed()

        if _.isFunction(@onChange) and not @equalsFunc oldValue, newValue
            # AutoDicts and AutoLists might get stopped before
            # onChange is called, but as long as they're not stopped
            # now, it makes sense to let onChange read their
            # preserved values.

            newPreservedValue = @_preservedValue
            Tracker.afterFlush @_bindEnvironment =>
                @onChange.call @, oldPreservedValue, newPreservedValue

    _setupValueComp: ->
        @_valueComp?.stop()
        lastValueResult = undefined
        @_valueComp = Tracker.nonreactive => Tracker.autorun @_bindEnvironment (valueComp) =>
            valueComp.tag = "AutoVar #{@tag}"

            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1

            try
                lastValueResult = @_recompute()
            catch e
                if Meteor.isClient and e is J.fetching.FETCH_IN_PROGRESS
                    lastValueResult = e
                else throw e

            @_getting = false

            valueComp.onInvalidate =>
                console.log "#{@tag} invalidated"
                unless valueComp.stopped
                    if @ not in @constructor._pending
                        @constructor._pending.push @

            if Meteor.isClient and lastValueResult is J.fetching.FETCH_IN_PROGRESS
                if valueComp.firstRun
                    # Meteor stops computations that error on
                    # their first run, so don't throw an error
                    # here.
                else throw e

        if Meteor.isClient and lastValueResult is J.fetching.FETCH_IN_PROGRESS
            # Now throw that error, after Meteor is done
            # setting up the first run.
            if Tracker.active
                throw J.fetching.FETCH_IN_PROGRESS


    contains: (x) ->
        # Reactive
        @indexOf(x) >= 0

    get: ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped: #{@}"
        if arguments.length
            throw new Meteor.Error "Can't pass argument to AutoVar.get"

        console.log "#{@tag}.get()", @_valueComp?._id, @constructor._pending
        @_getting = true
        if @_valueComp?
            @constructor.flush()
        else
            try
                @_setupValueComp()
            catch e
                if Meteor.isClient and e is J.fetching.FETCH_IN_PROGRESS
                    # Call this just to set up the dependency
                    # between @ and the caller.
                    @_deepGet()
                throw e

        @_deepGet()

    indexOf: (x) ->
        # Reactive
        value = Tracker.nonreactive =>
            v = @get()
            if v instanceof J.List then v.getValues() else v

        if not _.isArray(value)
            throw new Meteor.Error "Can't call .contains() on AutoVar with
                non-list value: #{J.util.stringify value}"

        i = value.indexOf x

        @_arrIndexOfDeps[x] ?= new Tracker.Dependency()
        @_arrIndexOfDeps[x].depend()

        i

    set: ->
        throw new Meteor.Error "There is no AutoVar.set"

    setDebug: (@debug) ->

    stop: ->
        if @active
            @active = false
            @_valueComp?.stop()
            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1

    toString: ->
        if @tag?
            "AutoVar(#{@tag}=#{J.util.stringify @_var.get()})"
        else
            "AutoVar(#{J.util.stringify @_var.get()})"


    @_pending: []

    @flush: ->
        while @_pending.length
            av = @_pending.shift()
            av._setupValueComp()

    # Internal classes return this in @_valueFunc
    # in order to make .get() return undefined
    @_UNDEFINED_WITHOUT_SET = {'AutoVar':'UNDEFINED_WITHOUT_SET'}