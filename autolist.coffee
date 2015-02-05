class J.AutoList extends J.List
    constructor: (sizeFunc, valueFunc, onChange = null, equalsFunc = J.util.equals) ->
        unless @ instanceof J.AutoList
            return new J.AutoList sizeFunc, valueFunc, onChange, equalsFunc

        unless _.isFunction(sizeFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoList must be constructed with sizeFunc and valueFunc"

        super [], equalsFunc

        @sizeFunc = sizeFunc
        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc

        @active = true
        if Tracker.active then Tracker.onInvalidate => @stop()

        @_dict = Tracker.nonreactive => J.AutoDict(
            => "#{i}" for i in [0...@sizeFunc()]
            (key) => @valueFunc parseInt(key)
            (
                if _.isFunction @onChange then (key, oldValue, newValue) =>
                    @onChange?.call @, parseInt(key), oldValue, newValue
                else
                    @onChange
            )
            @equalsFunc
        )

    clear: ->
        throw new Meteor.Error "There is no AutoList.clear"

    get: ->
        unless @active
            throw new Meteor.Error "AutoList is stopped"
        super

    push: ->
        throw new Meteor.Error "There is no AutoList.push"

    resize: ->
        throw new Meteor.Error "There is no AutoList.resize"

    reverse: ->
        throw new Meteor.Error "There is no AutoList.reverse"

    set: ->
        throw new Meteor.Error "There is no AutoList.set"

    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"

    stop: ->
        @_dict.stop()
        @active = false

    toString: ->
        # Reactive
        "AutoList#{J.util.stringify @toArr()}"