use yew::prelude::*;

#[function_component(App)]
fn app() -> Html {
    let count = use_state(|| 0);
    let onclick = {
        let count = count.clone();
        Callback::from(move |_| count.set(*count + 1))
    };
    html! {
        <div class="wrap">
            <h1>{ "Hello from Yew! \u{1F680}" }</h1>
            <p>{ "Built on your iPhone with YewBuilder and deployed to MikeGyver Studio." }</p>
            <div class="count">{ *count }</div>
            <button {onclick}>{ "Tap me" }</button>
            <footer>{ "YewBuilder — MikeGyver Studio · Sharing is Caring" }</footer>
        </div>
    }
}

fn main() {
    yew::Renderer::<App>::new().render();
}
