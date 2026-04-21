let headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'))

// generate id for all headings if there isn't one already
headings.forEach( (heading, index) => {
	if (!heading.id) {
		let parts = heading.textContent.trim().split(' ').concat([index])
		heading.id = parts.join('_')
	}
})

// create observer
let observer = new IntersectionObserver(function(entries) {
	for (index in entries) {
		let entry = entries[index]
		if (entry.isIntersecting === false && entry.boundingClientRect.top <= entry.rootBounds.top) {
			window.webkit.messageHandlers.headingVisible.postMessage({id: entry.target.id})
			return
		} else if (
			entry.isIntersecting === false &&
			entry.boundingClientRect.bottom > entry.rootBounds.bottom
		) {
			let index = headings.findIndex(element => element.id == entry.target.id )
			let previousHeading = headings[index - 1]
			window.webkit.messageHandlers.headingVisible.postMessage({id: previousHeading.id})
			console.log(previousHeading)
			return
		}
	}
}, { rootMargin: '-50px 0 -35% 0', threshold: 1.0 });

// register scroll view to handle heading on top of the page
window.onscroll = function() {
	if (document.documentElement.scrollTop <= 0) {
		const headingVisible = window.webkit.messageHandlers.headingVisible
		if(headingVisible !== undefined && headingVisible.postMessage !== undefined) {
			headingVisible.postMessage({id: headings[0].id})
		}
	}
}

// expand all detail tags
function expandAllDetailTags() {
	document.querySelectorAll('details').forEach( detail => detail.setAttribute('open', true) )	
}

// convert all headings into objects and send it to app side
function getOutlineItems() {
	window.webkit.messageHandlers.headings.postMessage(
		headings.map( heading => {
			return {
				id: heading.id,
				text: heading.textContent.trim(),
				tag: heading.tagName,
			}
		})
	)
}

// observe headings for intersection
function observeHeadings() {
	observer.disconnect()
	headings.forEach( heading => { observer.observe(heading) })
}

function scrollToHeading(id) {
	element = document.getElementById(id)
	element.scrollIntoView({block: 'start', inline: 'start', behavior: 'smooth'})
}

function pauseVideoWhenNotInPIP() {
    // make sure it's not in picture in picture mode:
    if (document.pictureInPictureElement != null) {
        return;
    }
    document.querySelectorAll("video").forEach((video) => {
        video.pause();
    });
}

function refreshVideoState() {
    // make sure it's not in picture in picture mode:
    if (document.pictureInPictureElement != null) {
        return;
    }
	
    document.querySelectorAll("video").forEach((video) => {
        if (video.paused && video.currentTime > 0) {
            video.play();
            video.pause();
        }
    });
}

function disableVideoContextMenu() {
    document.querySelectorAll("video").forEach((video) => {
        video.addEventListener("contextmenu", function(e) { e.preventDefault(); }, false);
    });
}

// Bridge the HTML5 Geolocation API to CoreLocation via a script message handler.
// This lets map ZIM files (e.g. WikiVoyage) use navigator.geolocation; the
// native side prompts the user for CoreLocation permission on first use.
// Supports both getCurrentPosition (one-shot) and watchPosition (continuous).
(function () {
    const handler = window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers.geolocation
    if (!handler) { return }

    const pending = new Map()
    let nextId = 1

    function deliverSuccess(success, payload) {
        if (typeof success !== 'function') { return }
        success({
            coords: {
                latitude: payload.coords.latitude,
                longitude: payload.coords.longitude,
                accuracy: payload.coords.accuracy,
                altitude: payload.coords.altitude ?? null,
                altitudeAccuracy: payload.coords.altitudeAccuracy ?? null,
                heading: payload.coords.heading ?? null,
                speed: payload.coords.speed ?? null
            },
            timestamp: payload.timestamp
        })
    }

    function deliverError(error, err) {
        if (typeof error !== 'function') { return }
        error({
            code: err.code,
            message: err.message,
            PERMISSION_DENIED: 1,
            POSITION_UNAVAILABLE: 2,
            TIMEOUT: 3
        })
    }

    window.__kiwixGeolocationResolve = function (id, payload) {
        const entry = pending.get(id)
        if (!entry) { return }
        if (payload && payload.coords) {
            deliverSuccess(entry.success, payload)
        } else if (payload && payload.error) {
            deliverError(entry.error, payload.error)
        }
        // One-shot requests are cleaned up after a single delivery; watches
        // are retained until clearWatch() is called from the page.
        if (!entry.isWatch) {
            pending.delete(id)
        }
    }

    function getCurrentPosition(success, error, options) {
        const id = nextId++
        pending.set(id, { success: success, error: error, isWatch: false })
        handler.postMessage({
            type: 'getCurrentPosition',
            id: id,
            highAccuracy: !!(options && options.enableHighAccuracy)
        })
    }

    function watchPosition(success, error, options) {
        const id = nextId++
        pending.set(id, { success: success, error: error, isWatch: true })
        handler.postMessage({
            type: 'watchPosition',
            id: id,
            highAccuracy: !!(options && options.enableHighAccuracy)
        })
        return id
    }

    function clearWatch(id) {
        if (!pending.has(id)) { return }
        pending.delete(id)
        handler.postMessage({ type: 'clearWatch', id: id })
    }

    try {
        Object.defineProperty(navigator, 'geolocation', {
            configurable: true,
            value: {
                getCurrentPosition: getCurrentPosition,
                watchPosition: watchPosition,
                clearWatch: clearWatch
            }
        })
    } catch (_) {
        // Fall through; native navigator.geolocation remains in place.
    }
})();

function fixVideoElements() {

    function fixVideoAttributes(element) {
        element.querySelectorAll("video").forEach((video) => {
            const attributes = video.attributes
            if(attributes.getNamedItem('poster')) {
                attributes.removeNamedItem('poster');
            }
            video.setAttribute('playsinline', '');
        });
    }

    // fix in the currently loaded DOM
    fixVideoAttributes(document);

    // observe the DOM, if video content is added, fix that as well
    var observeDOM = (function() {
        var MutationObserver = window.MutationObserver || window.WebKitMutationObserver;

        return function(obj, callback) {
            if (!obj || obj.nodeType !== 1) {
                return;
            }

            if (MutationObserver) {
                // define a new observer
                var mutationObserver = new MutationObserver(callback);
                // have the observer observe for changes in children
                mutationObserver.observe(obj, {attributes: false, childList: true, subtree: true});
                return mutationObserver;
            }
        }
    })();

    // Observe the body DOM element:
    observeDOM(document.querySelector('body'), function(mutationList) {
        for (const mutation of mutationList) {
            if (mutation.type === 'childList' & mutation.addedNodes.length) {
                for (const addedNode of mutation.addedNodes) {
                    if(addedNode.querySelectorAll) {
                        fixVideoAttributes(addedNode);
                    }
                }
            }
        }
    });
}
